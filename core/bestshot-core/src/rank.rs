//! Pairwise ranking: show two photos, pick the better one, repeat.
//!
//! A port of the original web app's Compare (`static/app.js` `recordWin`).
//! Every answer is closed transitively, so if A beat B and B beat C, A vs C
//! is never asked. On top of that sit undo and the ordering rules the Linux
//! app's Rank view uses.

use std::collections::hash_map::RandomState;
use std::collections::{HashMap, HashSet};
use std::hash::{BuildHasher, Hasher};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    /// Ask about every pair, from scratch.
    All,
    /// Keep the saved order as known results; only ask about unranked items.
    Unranked,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Choice {
    Left,
    Right,
    /// A tie: move on without recording a result.
    Skip,
}

#[derive(Debug, Clone)]
struct Engine {
    beats: HashMap<String, HashSet<String>>,
    loses_to: HashMap<String, HashSet<String>>,
    scores: HashMap<String, u32>,
    pairs: Vec<(String, String)>,
    index: usize,
    asked: u32,
    inferred: u32,
}

impl Engine {
    fn known(&self, a: &str, b: &str) -> bool {
        self.beats[a].contains(b) || self.beats[b].contains(a)
    }

    fn add(&mut self, winner: &str, loser: &str) -> bool {
        if !self.beats.get_mut(winner).unwrap().insert(loser.to_string()) {
            return false;
        }
        self.loses_to.get_mut(loser).unwrap().insert(winner.to_string());
        *self.scores.get_mut(winner).unwrap() += 1;
        true
    }

    /// Faithful port of `recordWin`.
    fn record_win(&mut self, winner: &str, loser: &str) {
        if !self.add(winner, loser) {
            return;
        }
        // The winner inherits everyone the loser beats.
        let loser_beats: Vec<String> = self.beats[loser].iter().cloned().collect();
        for item in &loser_beats {
            if self.add(winner, item) {
                self.inferred += 1;
            }
        }
        // Everyone who beats the winner now beats the loser and all it beats.
        let winner_losers: Vec<String> = self.loses_to[winner].iter().cloned().collect();
        let loser_beats: Vec<String> = self.beats[loser].iter().cloned().collect();
        for item in &winner_losers {
            if self.add(item, loser) {
                self.inferred += 1;
            }
            for sub in &loser_beats {
                if self.add(item, sub) {
                    self.inferred += 1;
                }
            }
        }
    }
}

/// One Compare session over string ids (Photos local identifiers or
/// folder-relative paths).
#[derive(Debug, Clone)]
pub struct RankSession {
    ids: Vec<String>,
    prior: Vec<String>,
    engine: Engine,
    history: Vec<Engine>,
}

const HISTORY_LIMIT: usize = 30;

impl RankSession {
    /// A session with pairs in random order.
    pub fn new(ids: Vec<String>, ranking: &[String], scope: Scope) -> Self {
        let mut rng = SplitMix::seeded();
        Self::with_shuffle(ids, ranking, scope, |pairs| rng.shuffle(pairs))
    }

    /// A session whose pair order is decided by `shuffle` (for tests).
    pub fn with_shuffle(
        ids: Vec<String>,
        ranking: &[String],
        scope: Scope,
        shuffle: impl FnOnce(&mut Vec<(String, String)>),
    ) -> Self {
        let pool: HashSet<&String> = ids.iter().collect();
        let prior: Vec<String> = ranking.iter().filter(|r| pool.contains(r)).cloned().collect();
        let prior_set: HashSet<&String> = prior.iter().collect();

        let mut engine = Engine {
            beats: ids.iter().map(|i| (i.clone(), HashSet::new())).collect(),
            loses_to: ids.iter().map(|i| (i.clone(), HashSet::new())).collect(),
            scores: ids.iter().map(|i| (i.clone(), 0)).collect(),
            pairs: Vec::new(),
            index: 0,
            asked: 0,
            inferred: 0,
        };
        if scope == Scope::Unranked {
            for (i, winner) in prior.iter().enumerate() {
                for loser in &prior[i + 1..] {
                    engine.add(winner, loser);
                }
            }
        }
        for (i, a) in ids.iter().enumerate() {
            for b in &ids[i + 1..] {
                if scope == Scope::All || !prior_set.contains(a) || !prior_set.contains(b) {
                    engine.pairs.push((a.clone(), b.clone()));
                }
            }
        }
        shuffle(&mut engine.pairs);
        Self { ids, prior, engine, history: Vec::new() }
    }

    /// The next pair whose result isn't already known, or `None` when done.
    pub fn current_pair(&mut self) -> Option<(String, String)> {
        while let Some((a, b)) = self.engine.pairs.get(self.engine.index) {
            if !self.engine.known(a, b) {
                return Some((a.clone(), b.clone()));
            }
            self.engine.index += 1;
        }
        None
    }

    pub fn choose(&mut self, choice: Choice) {
        let Some((a, b)) = self.current_pair() else { return };
        self.history.push(self.engine.clone());
        if self.history.len() > HISTORY_LIMIT {
            self.history.remove(0);
        }
        match choice {
            Choice::Left => self.engine.record_win(&a, &b),
            Choice::Right => self.engine.record_win(&b, &a),
            Choice::Skip => {}
        }
        self.engine.asked += 1;
        self.engine.index += 1;
    }

    pub fn undo(&mut self) -> bool {
        match self.history.pop() {
            Some(previous) => {
                self.engine = previous;
                true
            }
            None => false,
        }
    }

    pub fn can_undo(&self) -> bool {
        !self.history.is_empty()
    }

    pub fn is_finished(&self) -> bool {
        self.clone().current_pair().is_none()
    }

    /// Questions answered (including skips).
    pub fn asked(&self) -> u32 {
        self.engine.asked
    }

    /// Results worked out without asking.
    pub fn inferred(&self) -> u32 {
        self.engine.inferred
    }

    pub fn total_pairs(&self) -> u32 {
        self.engine.pairs.len() as u32
    }

    pub fn percent(&self) -> u32 {
        let total = self.total_pairs();
        if total == 0 {
            return 100;
        }
        ((100 * (self.asked() + self.inferred()).min(total)) / total).min(100)
    }

    /// Best first. Items with no known result stay unranked unless they were
    /// ranked before this session. Ties fall back to the previous rank, then
    /// to the order the ids were given in.
    pub fn order(&self) -> Vec<String> {
        let prior_rank: HashMap<&str, usize> =
            self.prior.iter().enumerate().map(|(i, id)| (id.as_str(), i)).collect();
        let position: HashMap<&str, usize> =
            self.ids.iter().enumerate().map(|(i, id)| (id.as_str(), i)).collect();
        let e = &self.engine;
        let mut out: Vec<String> = self
            .ids
            .iter()
            .filter(|id| {
                prior_rank.contains_key(id.as_str()) || !e.beats[*id].is_empty() || !e.loses_to[*id].is_empty()
            })
            .cloned()
            .collect();
        out.sort_by(|a, b| {
            e.scores[b]
                .cmp(&e.scores[a])
                .then_with(|| {
                    let pa = prior_rank.get(a.as_str()).copied().unwrap_or(usize::MAX);
                    let pb = prior_rank.get(b.as_str()).copied().unwrap_or(usize::MAX);
                    pa.cmp(&pb)
                })
                .then_with(|| position[a.as_str()].cmp(&position[b.as_str()]))
        });
        out
    }

    /// This session's order first, then anything in `saved` that wasn't in
    /// the pool (so ranking keepers doesn't forget photos ranked elsewhere).
    pub fn merged_ranking(&self, saved: &[String]) -> Vec<String> {
        let mut out = self.order();
        let placed: HashSet<String> = out.iter().cloned().collect();
        out.extend(saved.iter().filter(|s| !placed.contains(*s)).cloned());
        out
    }
}

/// A tiny PRNG for shuffling pairs; no extra dependency needed.
struct SplitMix(u64);

impl SplitMix {
    fn seeded() -> Self {
        // RandomState is seeded from the OS's random source.
        let mut h = RandomState::new().build_hasher();
        h.write_u64(0x5EED);
        Self(h.finish())
    }

    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    fn shuffle<T>(&mut self, items: &mut [T]) {
        for i in (1..items.len()).rev() {
            let j = (self.next() % (i as u64 + 1)) as usize;
            items.swap(i, j);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(s: &str) -> Vec<String> {
        s.chars().map(|c| c.to_string()).collect()
    }

    /// Answers every question truthfully against `truth` (best first).
    fn answer_all(s: &mut RankSession, truth: &str) -> u32 {
        let rank = |id: &str| truth.find(id).unwrap();
        let mut n = 0;
        while let Some((a, b)) = s.current_pair() {
            s.choose(if rank(&a) < rank(&b) { Choice::Left } else { Choice::Right });
            n += 1;
        }
        n
    }

    #[test]
    fn full_ranking_is_correct_and_inference_saves_questions() {
        let mut rng = SplitMix(42);
        let mut s = RankSession::with_shuffle(ids("hgfedcba"), &[], Scope::All, |p| rng.shuffle(p));
        let asked = answer_all(&mut s, "abcdefgh");
        assert_eq!(s.order(), ids("abcdefgh"));
        assert!(s.is_finished());
        assert!(asked < s.total_pairs(), "asked {asked} of {}", s.total_pairs());
        assert!(s.inferred() > 0);
        assert_eq!(s.percent(), 100);
    }

    #[test]
    fn fixed_pair_order_can_ask_every_pair() {
        // Pairs in generation order give inference nothing to work with; the
        // ranking must still come out right.
        let mut s = RankSession::with_shuffle(ids("hgfedcba"), &[], Scope::All, |_| {});
        assert_eq!(answer_all(&mut s, "abcdefgh"), 28);
        assert_eq!(s.order(), ids("abcdefgh"));
    }

    #[test]
    fn unranked_scope_slots_new_items_into_existing_order() {
        let mut s = RankSession::with_shuffle(ids("acebd"), &ids("ace"), Scope::Unranked, |_| {});
        answer_all(&mut s, "abcde");
        assert_eq!(s.order(), ids("abcde"));
    }

    #[test]
    fn undo_restores_the_previous_question() {
        let mut s = RankSession::with_shuffle(ids("xy"), &[], Scope::All, |_| {});
        let first = s.current_pair().unwrap();
        s.choose(Choice::Right);
        assert!(s.is_finished());
        assert_eq!(s.order(), ids("yx"));
        assert!(s.undo());
        assert_eq!(s.current_pair(), Some(first));
        assert!(s.order().is_empty());
        assert!(!s.undo());
    }

    #[test]
    fn partial_order_and_skips() {
        let mut s = RankSession::with_shuffle(ids("pqr"), &[], Scope::All, |_| {});
        s.choose(Choice::Left); // p beats q
        assert_eq!(s.order(), ids("pq"));

        let mut t = RankSession::with_shuffle(ids("pq"), &[], Scope::All, |_| {});
        t.choose(Choice::Skip);
        assert!(t.is_finished());
        assert!(t.order().is_empty());
    }

    #[test]
    fn merged_ranking_keeps_items_outside_the_pool() {
        let saved = vec!["z".to_string(), "b".to_string(), "a".to_string()];
        let mut s = RankSession::with_shuffle(ids("ab"), &saved, Scope::All, |_| {});
        s.choose(Choice::Left); // a beats b
        assert_eq!(s.merged_ranking(&saved), vec!["a", "b", "z"]);
    }

    #[test]
    fn random_sessions_always_rank_correctly() {
        let truth = "abcdefghijklmnop";
        for _ in 0..20 {
            let mut s = RankSession::new(ids(truth).into_iter().rev().collect(), &[], Scope::All);
            answer_all(&mut s, truth);
            assert_eq!(s.order(), ids(truth));
        }
    }
}
