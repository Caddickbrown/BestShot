"use strict";

// Rank mode: put photos in order, best first.
// Compare is a port of the web app's pairwise ranking (static/app.js
// `recordWin`): every answer is propagated transitively, so if A beat B and
// B beat C you're never asked about A vs C.

const RankEngine = (() => {
  function shuffle(list) {
    for (let i = list.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [list[i], list[j]] = [list[j], list[i]];
    }
    return list;
  }

  /**
   * names: everything taking part. ranked: existing order (best first).
   * scope "new" keeps the existing order as known results and only asks about
   * pairs involving an unranked photo; "all" starts from scratch.
   */
  function create(names, ranked, scope) {
    const scores = {};
    const beats = {};
    const losesTo = {};
    for (const n of names) {
      scores[n] = 0;
      beats[n] = new Set();
      losesTo[n] = new Set();
    }
    const inPool = new Set(names);
    const prior = ranked.filter((n) => inPool.has(n));
    const unranked = new Set(names.filter((n) => !prior.includes(n)));

    if (scope === "new") {
      for (let i = 0; i < prior.length; i++) {
        for (let j = i + 1; j < prior.length; j++) {
          beats[prior[i]].add(prior[j]);
          losesTo[prior[j]].add(prior[i]);
          scores[prior[i]]++;
        }
      }
    }

    const pairs = [];
    for (let i = 0; i < names.length; i++) {
      for (let j = i + 1; j < names.length; j++) {
        if (scope === "all" || unranked.has(names[i]) || unranked.has(names[j])) pairs.push([names[i], names[j]]);
      }
    }

    return {
      names,
      scope,
      prior,
      scores,
      beats,
      losesTo,
      pairs: shuffle(pairs),
      index: 0,
      asked: 0,
      inferred: 0,
      history: [],
    };
  }

  const known = (c, a, b) => c.beats[a].has(b) || c.beats[b].has(a);

  function recordWin(c, winner, loser) {
    const { beats, losesTo, scores } = c;
    if (beats[winner].has(loser)) return;
    beats[winner].add(loser);
    losesTo[loser].add(winner);
    scores[winner]++;

    for (const item of beats[loser]) {
      if (!beats[winner].has(item)) {
        beats[winner].add(item);
        losesTo[item].add(winner);
        scores[winner]++;
        c.inferred++;
      }
    }
    for (const item of losesTo[winner]) {
      if (!beats[item].has(loser)) {
        beats[item].add(loser);
        losesTo[loser].add(item);
        scores[item]++;
        c.inferred++;
      }
      for (const sub of beats[loser]) {
        if (!beats[item].has(sub)) {
          beats[item].add(sub);
          losesTo[sub].add(item);
          scores[item]++;
          c.inferred++;
        }
      }
    }
  }

  /** The next pair whose result isn't already known, or null when done. */
  function current(c) {
    while (c.index < c.pairs.length) {
      const [a, b] = c.pairs[c.index];
      if (!known(c, a, b)) return [a, b];
      c.index++;
    }
    return null;
  }

  function snapshot(c) {
    const copy = (m) => Object.fromEntries(Object.entries(m).map(([k, v]) => [k, new Set(v)]));
    return {
      scores: { ...c.scores },
      beats: copy(c.beats),
      losesTo: copy(c.losesTo),
      index: c.index,
      asked: c.asked,
      inferred: c.inferred,
    };
  }

  /** side: "left" | "right" | "skip" (a tie: move on without a result). */
  function choose(c, side) {
    const pair = current(c);
    if (!pair) return;
    c.history.push(snapshot(c));
    if (c.history.length > 30) c.history.shift();
    if (side === "left") recordWin(c, pair[0], pair[1]);
    else if (side === "right") recordWin(c, pair[1], pair[0]);
    c.asked++;
    c.index++;
  }

  function undo(c) {
    const prev = c.history.pop();
    if (!prev) return false;
    Object.assign(c, prev);
    return true;
  }

  /**
   * Best first. Photos with no known result at all stay unranked, unless they
   * were already ranked before this session.
   */
  function order(c) {
    const prior = new Set(c.prior);
    const position = new Map(c.names.map((n, i) => [n, i]));
    const involved = (n) => prior.has(n) || c.beats[n].size > 0 || c.losesTo[n].size > 0;
    const priorRank = new Map(c.prior.map((n, i) => [n, i]));
    return c.names
      .filter(involved)
      .sort(
        (a, b) =>
          c.scores[b] - c.scores[a] ||
          (priorRank.get(a) ?? Infinity) - (priorRank.get(b) ?? Infinity) ||
          position.get(a) - position.get(b),
      );
  }

  function progress(c) {
    const total = c.pairs.length;
    const done = Math.min(total, c.asked + c.inferred);
    return { total, percent: total ? Math.round((100 * done) / total) : 100, asked: c.asked, inferred: c.inferred };
  }

  return { create, choose, undo, current, order, progress, recordWin };
})();

if (typeof module !== "undefined") {
  module.exports = RankEngine;
} else {
  // ============ Rank view ============

  const R = { pool: "keep", compare: null };

  /** Item indices taking part in ranking: keepers, or everything not rejected. */
  function rankPool() {
    const out = [];
    S.items.forEach((item, i) => {
      const d = S.decisions.get(item.rel);
      if (R.pool === "keep" ? d === "keep" : d !== "reject") out.push(i);
    });
    return out;
  }

  function indexByRel() {
    return new Map(S.items.map((item, i) => [item.rel, i]));
  }

  /** { ranked: indices best first, unranked: indices in folder order } */
  function rankLists() {
    const pool = rankPool();
    const inPool = new Set(pool);
    const byRel = indexByRel();
    const ranked = S.ranking.map((rel) => byRel.get(rel)).filter((i) => i != null && inPool.has(i));
    const rankedSet = new Set(ranked);
    return { ranked, unranked: pool.filter((i) => !rankedSet.has(i)) };
  }

  function saveRanking(rels) {
    // Photos outside the current pool keep their saved place at the end.
    const keep = new Set(rels);
    S.ranking = [...rels, ...S.ranking.filter((rel) => !keep.has(rel))];
    const gen = S.gen;
    const ranking = S.ranking;
    saveChain = saveChain
      .then(() => invoke("set_ranking", { gen, ranking }))
      .catch((err) => toast(`Couldn't save ranking: ${err}`, true));
  }

  function renderRank() {
    const { ranked, unranked } = rankLists();
    const kept = S.items.filter((it) => S.decisions.get(it.rel) === "keep").length;
    const notRejected = S.items.filter((it) => S.decisions.get(it.rel) !== "reject").length;
    for (const btn of $("rank-pool").children) {
      btn.classList.toggle("active", btn.dataset.pool === R.pool);
      btn.querySelector("span").textContent = fmt(btn.dataset.pool === "keep" ? kept : notRejected);
    }

    const total = ranked.length + unranked.length;
    $("rank-status").textContent = total
      ? `${fmt(ranked.length)} ranked · ${fmt(unranked.length)} new · drag to reorder`
      : "";
    $("rank-compare-new").textContent = unranked.length ? `Compare new (${fmt(unranked.length)})` : "Compare new";
    $("rank-compare-new").disabled = unranked.length === 0 || total < 2;
    $("rank-compare-all").disabled = total < 2;
    $("rank-clear").disabled = ranked.length === 0;
    $("rank-compare-new").classList.toggle("primary", unranked.length > 0);
    $("rank-compare-all").classList.toggle("primary", unranked.length === 0 && total >= 2);

    const sheet = $("rank-sheet");
    if (!total) {
      sheet.replaceChildren(
        el("p", {
          className: "rank-empty",
          textContent:
            R.pool === "keep"
              ? "No keepers yet. Mark photos with → or P, or switch to “Not rejected” to rank everything."
              : "Nothing to rank in this folder.",
        }),
      );
      return;
    }

    const tile = (i, rank) => {
      const item = S.items[i];
      const node = el(
        "div",
        { className: `rank-tile ${rank && rank <= 3 ? "podium" : ""}`, title: item.rel },
        el("img", { src: thumbUrl(i), loading: "lazy", draggable: false }),
      );
      if (rank) node.append(el("span", { className: "rank-no", textContent: rank }));
      if (item.kind === "video") node.append(el("span", { className: "video-mark", textContent: "▶" }));
      node.dataset.i = i;
      return node;
    };

    const rankedGrid = el("div", { className: "rank-grid ranked" }, ...ranked.map((i, k) => tile(i, k + 1)));
    rankedGrid.id = "rank-ranked";
    const parts = [];
    if (ranked.length) {
      parts.push(rankedGrid);
    } else {
      // Still a drop target, so photos can be dragged up into the ranking.
      rankedGrid.append(el("p", { className: "rank-drop-hint", textContent: "Drag photos here, or press Compare." }));
      parts.push(rankedGrid);
    }
    if (unranked.length) {
      parts.push(
        el("h3", { className: "rank-divider", textContent: `Not ranked yet · ${fmt(unranked.length)}` }),
        el("div", { className: "rank-grid unranked" }, ...unranked.map((i) => tile(i, 0))),
      );
    }
    sheet.replaceChildren(...parts);
  }

  // ---- Drag to reorder (mouse; on touch a tap opens the photo) ----

  let drag = null;

  function setupRankDrag() {
    const sheet = $("rank-sheet");

    sheet.addEventListener("pointerdown", (e) => {
      const tile = e.target.closest(".rank-tile");
      if (!tile || e.button > 0) return;
      drag = { tile, id: e.pointerId, x: e.clientX, y: e.clientY, active: false, ghost: null, mouse: e.pointerType === "mouse" };
    });

    window.addEventListener("pointermove", (e) => {
      if (!drag || e.pointerId !== drag.id) return;
      const moved = Math.hypot(e.clientX - drag.x, e.clientY - drag.y);
      if (!drag.active) {
        if (!drag.mouse && moved > 10) {
          drag = null; // a touch scroll, not a tap
          return;
        }
        if (drag.mouse && moved > 6) startDrag(e);
        if (!drag.active) return;
      }
      e.preventDefault();
      drag.ghost.style.transform = `translate(${e.clientX - drag.offX}px, ${e.clientY - drag.offY}px)`;
      updateDropTarget(e.clientX, e.clientY);
      autoScroll(e.clientY);
    });

    const end = (e) => {
      if (!drag || e.pointerId !== drag.id) return;
      const finished = drag;
      drag = null;
      if (!finished.active) {
        // A plain click: open the photo.
        if (e.type === "pointerup") {
          S.index = Number(finished.tile.dataset.i);
          setView("loupe");
        }
        return;
      }
      finished.ghost.remove();
      finished.tile.classList.remove("dragging");
      document.body.classList.remove("rank-dragging");
      const target = finished.target;
      clearDropMarks();
      if (target && e.type === "pointerup") dropAt(Number(finished.tile.dataset.i), target);
    };
    window.addEventListener("pointerup", end);
    window.addEventListener("pointercancel", end);
  }

  function startDrag(e) {
    if (!drag) return;
    const rect = drag.tile.getBoundingClientRect();
    drag.active = true;
    drag.offX = drag.x - rect.left;
    drag.offY = drag.y - rect.top;
    drag.ghost = drag.tile.cloneNode(true);
    drag.ghost.classList.add("rank-ghost");
    drag.ghost.style.width = `${rect.width}px`;
    drag.ghost.style.height = `${rect.height}px`;
    drag.ghost.style.transform = `translate(${rect.left}px, ${rect.top}px)`;
    document.body.append(drag.ghost);
    drag.tile.classList.add("dragging");
    document.body.classList.add("rank-dragging");
    updateDropTarget(e.clientX ?? drag.x, e.clientY ?? drag.y);
  }

  function clearDropMarks() {
    document.querySelectorAll(".drop-before, .drop-after, .drop-into").forEach((n) => {
      n.classList.remove("drop-before", "drop-after", "drop-into");
    });
  }

  /** Works out where a drop would land: before/after a ranked tile, or the end of the ranking. */
  function updateDropTarget(x, y) {
    clearDropMarks();
    drag.target = null;
    const under = document.elementFromPoint(x, y);
    const rankedGrid = $("rank-ranked");
    if (!under || !rankedGrid) return;
    const over = under.closest("#rank-ranked .rank-tile");
    if (over && over !== drag.tile) {
      const r = over.getBoundingClientRect();
      const after = x > r.left + r.width / 2;
      over.classList.add(after ? "drop-after" : "drop-before");
      drag.target = { i: Number(over.dataset.i), after };
    } else if (under.closest("#rank-ranked") && !over) {
      rankedGrid.classList.add("drop-into");
      drag.target = { end: true };
    }
  }

  function dropAt(moving, target) {
    const { ranked } = rankLists();
    const order = ranked.filter((i) => i !== moving);
    let at = order.length;
    if (!target.end) {
      at = order.indexOf(target.i);
      if (at < 0) return;
      if (target.after) at++;
    }
    order.splice(at, 0, moving);
    saveRanking(order.map((i) => S.items[i].rel));
    renderRank();
  }

  function autoScroll(y) {
    const sheet = $("rank-sheet");
    const r = sheet.getBoundingClientRect();
    if (y < r.top + 60) sheet.scrollTop -= 18;
    else if (y > r.bottom - 60) sheet.scrollTop += 18;
  }

  // ============ Compare ============

  function startCompare(scope) {
    const { ranked, unranked } = rankLists();
    const names = [...ranked, ...unranked].map((i) => S.items[i].rel);
    if (names.length < 2) return;
    R.compare = RankEngine.create(names, S.ranking, scope);
    R.byRel = indexByRel();
    $("compare-results").hidden = true;
    $("compare-pair").hidden = false;
    $("compare").hidden = false;
    showPair();
  }

  function mediaInto(side, rel) {
    const fig = $(side);
    const i = R.byRel.get(rel);
    const item = S.items[i];
    const img = fig.querySelector("img");
    const video = fig.querySelector("video");
    fig.querySelector(".name").textContent = basename(rel);
    fig.title = rel;
    if (item.kind === "video") {
      img.hidden = true;
      video.hidden = false;
      video.src = videoBase ? `${videoBase}/${S.gen}/${i}` : fullUrl(i);
      video.play().catch(() => {});
    } else {
      video.pause();
      video.removeAttribute("src");
      video.hidden = true;
      img.hidden = false;
      // Thumbnail first for an instant swap, then the full image.
      img.src = thumbUrl(i);
      const full = new Image();
      full.onload = () => R.compare && fig.title === rel && (img.src = full.src);
      full.src = fullUrl(i);
    }
  }

  const comparePreload = new Map();

  function preloadPairs() {
    const c = R.compare;
    const wanted = new Set();
    for (let k = c.index + 1, n = 0; k < c.pairs.length && n < 4; k++) {
      const [a, b] = c.pairs[k];
      if (c.beats[a].has(b) || c.beats[b].has(a)) continue;
      n++;
      for (const rel of [a, b]) {
        const i = R.byRel.get(rel);
        if (S.items[i].kind !== "image") continue;
        const url = fullUrl(i);
        wanted.add(url);
        if (!comparePreload.has(url)) {
          const img = new Image();
          img.src = url;
          comparePreload.set(url, img);
        }
      }
    }
    for (const url of comparePreload.keys()) if (!wanted.has(url)) comparePreload.delete(url);
  }

  function showPair() {
    const c = R.compare;
    const pair = RankEngine.current(c);
    if (!pair) {
      showCompareResults();
      return;
    }
    mediaInto("compare-left", pair[0]);
    mediaInto("compare-right", pair[1]);
    const p = RankEngine.progress(c);
    $("compare-progress").textContent =
      `${p.percent}% · comparison ${fmt(p.asked + 1)}` + (p.inferred ? ` · ${fmt(p.inferred)} inferred` : "");
    $("compare-undo").disabled = c.history.length === 0;
    $("compare-skip").disabled = false;
    preloadPairs();
  }

  function choose(side) {
    if (!R.compare || !$("compare-results").hidden) return;
    RankEngine.choose(R.compare, side);
    const fig = side === "left" ? $("compare-left") : side === "right" ? $("compare-right") : null;
    if (fig) {
      fig.classList.remove("picked");
      void fig.offsetWidth;
      fig.classList.add("picked");
    }
    showPair();
  }

  function compareUndo() {
    if (!R.compare) return;
    $("compare-results").hidden = true;
    $("compare-pair").hidden = false;
    if (RankEngine.undo(R.compare)) showPair();
  }

  function showCompareResults() {
    const c = R.compare;
    const total = c.pairs.length;
    const saved = total ? Math.round((1 - c.asked / total) * 100) : 0;
    $("compare-summary").textContent =
      `${plural(c.names.length, "photo")} ranked in ${plural(c.asked, "comparison")}` +
      (c.inferred ? `, with ${fmt(c.inferred)} worked out automatically` : "") +
      (saved > 0 ? ` (${saved}% fewer than comparing every pair).` : ".");
    $("compare-progress").textContent = `Done · ${plural(c.asked, "comparison")}`;
    $("compare-skip").disabled = true;
    $("compare-undo").disabled = c.history.length === 0;
    $("compare-pair").hidden = true;
    $("compare-results").hidden = false;
    stopCompareMedia();
  }

  function stopCompareMedia() {
    for (const v of $("compare").querySelectorAll("video")) {
      v.pause();
      v.removeAttribute("src");
    }
  }

  function closeCompare(save) {
    const c = R.compare;
    if (save && c && c.asked > 0) {
      saveRanking(RankEngine.order(c));
      toast(`Ranking saved: ${plural(c.asked, "comparison")}`);
    }
    R.compare = null;
    comparePreload.clear();
    stopCompareMedia();
    $("compare").hidden = true;
    renderRank();
  }

  // ============ Keys & wiring ============

  // Called by app.js's key handler while the Rank view is showing.
  function rankKey(e) {
    const k = e.key;
    if (R.compare) {
      const resultsOpen = !$("compare-results").hidden;
      if ((e.ctrlKey || e.metaKey) && k.toLowerCase() === "z") compareUndo();
      else if (e.ctrlKey || e.metaKey || e.altKey) return;
      else if (resultsOpen && k === "Enter") closeCompare(true);
      else if (k === "ArrowLeft" || k === "1") choose("left");
      else if (k === "ArrowRight" || k === "2") choose("right");
      else if (k === " " || k === "s" || k === "S") choose("skip");
      else if (k === "Backspace") compareUndo();
      else if (k === "Escape") closeCompare(true);
      else return;
      e.preventDefault();
      return;
    }
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (k === "Escape" || k === "r" || k === "R") setView("loupe");
    else if (k === "g" || k === "G") setView("grid");
    else if (k === "c" || k === "C") {
      const { unranked } = rankLists();
      startCompare(unranked.length && S.ranking.length ? "new" : "all");
    } else return;
    e.preventDefault();
  }

  function initRank() {
    setupRankDrag();
    $("rank-pool").addEventListener("click", (e) => {
      const btn = e.target.closest("button");
      if (!btn) return;
      R.pool = btn.dataset.pool;
      renderRank();
    });
    $("rank-compare-all").addEventListener("click", () => startCompare("all"));
    $("rank-compare-new").addEventListener("click", () => startCompare("new"));
    $("rank-clear").addEventListener("click", () => {
      const { ranked } = rankLists();
      if (!ranked.length) return;
      const drop = new Set(ranked.map((i) => S.items[i].rel));
      S.ranking = S.ranking.filter((rel) => !drop.has(rel));
      saveRanking([]);
      renderRank();
      toast(`Cleared the ranking of ${plural(ranked.length, "photo")}`);
    });

    $("compare-left").addEventListener("click", () => choose("left"));
    $("compare-right").addEventListener("click", () => choose("right"));
    $("compare-skip").addEventListener("click", () => choose("skip"));
    $("compare-undo").addEventListener("click", compareUndo);
    $("compare-exit").addEventListener("click", () => closeCompare(true));
    $("compare-apply").addEventListener("click", () => closeCompare(true));
    $("compare-discard").addEventListener("click", () => closeCompare(false));
    $("compare").addEventListener("click", (e) => e.target.closest("button")?.blur());
  }

  initRank();
  // Declared in a block, so hand app.js the two functions it calls.
  Object.assign(window, { renderRank, rankKey });
}
