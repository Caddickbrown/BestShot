"use strict";

const { invoke } = window.__TAURI__.core;
const { open: openDialog } = window.__TAURI__.dialog;

const $ = (id) => document.getElementById(id);

// Custom protocol served by the Rust side (see `register_asynchronous_uri_scheme_protocol`).
const MEDIA_BASE = /Windows/.test(navigator.userAgent) ? "http://bestshot.localhost" : "bestshot://localhost";
const RECENTS_KEY = "bestshot.recents";
const OPTIONS_KEY = "bestshot.options";
const PRELOAD_AHEAD = 3;

const S = {
  gen: 0,
  root: "",
  name: "",
  items: [],
  decisions: new Map(), // rel -> "keep" | "reject"
  index: 0,
  undo: [], // { index, prev }
  view: "loupe", // "loupe" | "grid"
  filter: "all",
  info: false,
  zoomed: false,
  lastPointer: null,
  options: { recursive: true, videos: true },
};

let videoBase = null; // loopback HTTP server; WebKitGTK can't stream video from custom schemes
const thumbUrl = (i) => `${MEDIA_BASE}/thumb/${S.gen}/${i}`;
const fullUrl = (i) => `${MEDIA_BASE}/full/${S.gen}/${i}`;
const decisionOf = (i) => S.decisions.get(S.items[i].rel) ?? null;

// ============ Utilities ============

function formatBytes(n) {
  if (n < 1024) return `${n} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let u = -1;
  do {
    n /= 1024;
    u++;
  } while (n >= 1024 && u < units.length - 1);
  return `${n.toFixed(n < 10 ? 1 : 0)} ${units[u]}`;
}

const fmt = (n) => n.toLocaleString();
const plural = (n, word) => `${fmt(n)} ${word}${n === 1 ? "" : "s"}`;
const basename = (rel) => rel.slice(rel.lastIndexOf("/") + 1);
const dirname = (rel) => (rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  Object.assign(node, props);
  node.append(...children);
  return node;
}

let toastTimer;
function toast(message, isError = false) {
  const t = $("toast");
  t.textContent = message;
  t.classList.toggle("error", isError);
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (t.hidden = true), isError ? 7000 : 2800);
}

// ============ Home: options, recents, opening ============

function loadOptions() {
  try {
    Object.assign(S.options, JSON.parse(localStorage.getItem(OPTIONS_KEY)) || {});
  } catch {}
  $("opt-recursive").checked = S.options.recursive;
  $("opt-videos").checked = S.options.videos;
}

function saveOptions() {
  S.options.recursive = $("opt-recursive").checked;
  S.options.videos = $("opt-videos").checked;
  localStorage.setItem(OPTIONS_KEY, JSON.stringify(S.options));
}

function loadRecents() {
  try {
    return JSON.parse(localStorage.getItem(RECENTS_KEY)) || [];
  } catch {
    return [];
  }
}

function rememberRecent() {
  if (!S.root) return;
  const { reviewed, total } = counts();
  const list = loadRecents().filter((r) => r.path !== S.root);
  list.unshift({ path: S.root, name: S.name, reviewed, total });
  localStorage.setItem(RECENTS_KEY, JSON.stringify(list.slice(0, 8)));
}

function renderRecents() {
  const list = loadRecents();
  $("recents").hidden = list.length === 0;
  $("recent-list").replaceChildren(
    ...list.map((r) => {
      const progress = r.total ? ` · ${fmt(r.reviewed)} of ${fmt(r.total)} reviewed` : "";
      const openBtn = el(
        "button",
        { className: "recent-open", title: r.path },
        el("strong", { textContent: r.name || r.path }),
        el("small", { textContent: r.path + progress }),
      );
      openBtn.addEventListener("click", () => openFolder(r.path));
      const removeBtn = el("button", { className: "recent-remove", title: "Remove from list", textContent: "×" });
      removeBtn.addEventListener("click", () => {
        localStorage.setItem(RECENTS_KEY, JSON.stringify(loadRecents().filter((x) => x.path !== r.path)));
        renderRecents();
      });
      return el("li", {}, openBtn, removeBtn);
    }),
  );
}

async function chooseFolder() {
  const path = await openDialog({ directory: true, multiple: false, title: "Choose a folder of photos" });
  if (path) openFolder(path);
}

async function openFolder(path, { message = "Scanning folder…" } = {}) {
  $("scanning-text").textContent = message;
  $("scanning").hidden = false;
  try {
    const info = await invoke("open_folder", {
      path,
      recursive: S.options.recursive,
      includeVideos: S.options.videos,
    });
    if (info.warning) toast(info.warning, true);
    if (info.items.length === 0) {
      toast(`No photos found in ${info.name || path}`, true);
      showHome();
      return;
    }
    Object.assign(S, {
      gen: info.gen,
      root: info.root,
      name: info.name || info.root,
      items: info.items,
      decisions: new Map(Object.entries(info.decisions)),
      undo: [],
      filter: "all",
    });
    preloaded.clear();
    rememberRecent();
    S.index = nextUnreviewed(0) ?? 0;
    showReview();
  } catch (err) {
    toast(String(err), true);
  } finally {
    $("scanning").hidden = true;
  }
}

function showHome() {
  rememberRecent();
  S.root = "";
  $("video").pause();
  $("review").hidden = true;
  $("home").hidden = false;
  renderRecents();
  setTitle("BestShot");
}

function showReview() {
  $("home").hidden = true;
  $("review").hidden = false;
  $("folder-name").textContent = S.name;
  $("folder-name").title = S.root;
  setTitle(`${S.name} — BestShot`);
  setView("loupe");
}

function setTitle(title) {
  document.title = title;
  window.__TAURI__.window.getCurrentWindow().setTitle(title).catch(() => {});
}

// ============ Decisions ============

let saveChain = Promise.resolve();

function setDecision(i, decision) {
  const rel = S.items[i].rel;
  if (decision) S.decisions.set(rel, decision);
  else S.decisions.delete(rel);
  // Serialise writes so a quick decide-then-undo can't land out of order.
  const gen = S.gen;
  saveChain = saveChain
    .then(() => invoke("set_decision", { gen, rel, decision }))
    .catch((err) => toast(`Couldn't save decision: ${err}`, true));
  rememberRecent();
}

function counts() {
  let keep = 0;
  let reject = 0;
  for (const item of S.items) {
    const d = S.decisions.get(item.rel);
    if (d === "keep") keep++;
    else if (d === "reject") reject++;
  }
  const total = S.items.length;
  return { keep, reject, total, reviewed: keep + reject, left: total - keep - reject };
}

function nextUnreviewed(from) {
  const n = S.items.length;
  for (let k = 0; k < n; k++) {
    const j = (from + k) % n;
    if (!S.decisions.has(S.items[j].rel)) return j;
  }
  return null;
}

function decide(decision) {
  const i = S.index;
  const prev = decisionOf(i);
  if (prev !== decision) {
    setDecision(i, decision);
    S.undo.push({ index: i, prev });
    if (S.undo.length > 1000) S.undo.shift();
  }
  flash(decision);

  if (counts().left === 0) {
    show(Math.min(i + 1, S.items.length - 1));
    showDone();
  } else if (i < S.items.length - 1) {
    show(i + 1);
  } else {
    show(nextUnreviewed(0));
    toast("Back to the first photo you skipped");
  }
}

function undo() {
  const last = S.undo.pop();
  if (!last) {
    toast("Nothing to undo");
    return;
  }
  setDecision(last.index, last.prev);
  if (S.view === "grid") renderGrid();
  else show(last.index);
}

function clearDecision() {
  const prev = decisionOf(S.index);
  if (!prev) return;
  setDecision(S.index, null);
  S.undo.push({ index: S.index, prev });
  show(S.index);
}

function flash(decision) {
  const f = $("flash");
  f.className = "flash";
  void f.offsetWidth; // restart the animation
  f.className = `flash ${decision}`;
  f.textContent = decision === "keep" ? "✓" : "✕";
}

// ============ Loupe ============

const preloaded = new Map(); // url -> Image, kept alive so WebKit keeps them decoded
let showToken = 0;

function show(i) {
  if (i == null || !S.items.length) return;
  S.index = Math.max(0, Math.min(i, S.items.length - 1));
  const item = S.items[S.index];
  const key = `${S.gen}/${S.index}`;
  const stage = $("stage");
  const photo = $("photo");
  const placeholder = $("placeholder");
  const video = $("video");

  $("done-card").hidden = true;
  setZoom(false);

  if (stage.dataset.key !== key) {
    stage.dataset.key = key;
    const token = ++showToken;
    $("media-error").hidden = true;

    if (item.kind === "video") {
      photo.hidden = placeholder.hidden = true;
      photo.removeAttribute("src");
      video.hidden = false;
      video.muted = true;
      video.src = videoBase ? `${videoBase}/${S.gen}/${S.index}` : fullUrl(S.index);
      video.play().catch(() => {});
    } else {
      video.pause();
      video.removeAttribute("src");
      video.load();
      video.hidden = true;
      photo.hidden = placeholder.hidden = false;
      photo.classList.remove("loaded");
      placeholder.src = thumbUrl(S.index);
      photo.onload = () => token === showToken && photo.classList.add("loaded");
      photo.onerror = () => token === showToken && showMediaError(photo.src);
      photo.src = fullUrl(S.index);
      if (photo.complete && photo.naturalWidth) photo.classList.add("loaded");
    }
    preloadAround(S.index);
  }

  const decision = decisionOf(S.index);
  stage.classList.toggle("decided-keep", decision === "keep");
  stage.classList.toggle("decided-reject", decision === "reject");
  const badge = $("badge");
  badge.className = `badge ${decision ?? ""}`;
  badge.textContent = decision ? decision.toUpperCase() : "";

  $("position").textContent = `${fmt(S.index + 1)} / ${fmt(S.items.length)} · ${item.rel}`;
  updateProgress();
  renderFilmstrip();
  if (S.info) renderInfo();
}

async function showMediaError(url) {
  let message = "This file couldn't be displayed.";
  try {
    const res = await fetch(url);
    if (!res.ok) message = await res.text();
  } catch {}
  $("media-error-text").textContent = message;
  $("media-error").hidden = false;
}

function preloadAround(i) {
  const wanted = new Set();
  for (let j = i - 1; j <= i + PRELOAD_AHEAD; j++) {
    if (j < 0 || j >= S.items.length || j === i || S.items[j].kind !== "image") continue;
    const url = fullUrl(j);
    wanted.add(url);
    if (!preloaded.has(url)) {
      const img = new Image();
      img.decoding = "async";
      img.src = url;
      preloaded.set(url, img);
    }
  }
  for (const url of preloaded.keys()) if (!wanted.has(url)) preloaded.delete(url);
}

function updateProgress() {
  const c = counts();
  $("n-keep").textContent = fmt(c.keep);
  $("n-reject").textContent = fmt(c.reject);
  $("n-left").textContent = fmt(c.left);
  document.querySelector(".bar .keep").style.width = `${(100 * c.keep) / c.total}%`;
  document.querySelector(".bar .reject").style.width = `${(100 * c.reject) / c.total}%`;
}

function showDone() {
  const c = counts();
  $("done-summary").textContent =
    `${plural(c.total, "photo")}: ${fmt(c.keep)} kept, ${fmt(c.reject)} rejected. ` +
    (c.reject ? "Check the rejects or finish to clear them out." : "Nothing to clear out.");
  $("done-rejects").hidden = c.reject === 0;
  $("done-card").hidden = false;
}

function renderFilmstrip() {
  const strip = $("filmstrip");
  const slots = Math.max(3, Math.floor((strip.clientWidth + 4) / 68)) | 1;
  if (strip.children.length !== slots) {
    strip.replaceChildren(
      ...Array.from({ length: slots }, () => {
        const tile = el("div", { className: "strip-tile" }, el("img", { draggable: false }));
        tile.addEventListener("click", () => show(Number(tile.dataset.i)));
        return tile;
      }),
    );
  }
  const half = slots >> 1;
  [...strip.children].forEach((tile, k) => {
    const j = S.index - half + k;
    if (j < 0 || j >= S.items.length) {
      tile.className = "strip-tile gap";
      return;
    }
    const decision = decisionOf(j);
    tile.className = `strip-tile ${decision ?? ""} ${j === S.index ? "current" : ""}`;
    tile.title = S.items[j].rel;
    const key = `${S.gen}/${j}`;
    if (tile.dataset.key !== key) {
      tile.dataset.key = key;
      tile.dataset.i = j;
      const img = tile.querySelector("img");
      img.style.visibility = "";
      img.src = thumbUrl(j);
      tile.querySelector(".video-mark")?.remove();
      if (S.items[j].kind === "video") tile.append(el("span", { className: "video-mark", textContent: "▶" }));
    }
  });
}

// ---- Zoom: click or Z for 100%, pointer position pans (Lightroom-style) ----

function setZoom(on, pointer) {
  const item = S.items[S.index];
  if (on && (item?.kind !== "image" || !$("photo").classList.contains("loaded"))) return;
  S.zoomed = on;
  $("stage").classList.toggle("zoomed", on);
  if (on) pan(pointer);
  else $("photo").style.objectPosition = "";
}

function pan(pointer) {
  const r = $("stage").getBoundingClientRect();
  const clamp = (v) => Math.max(0, Math.min(1, v));
  const fx = pointer ? clamp((pointer.x - r.left) / r.width) : 0.5;
  const fy = pointer ? clamp((pointer.y - r.top) / r.height) : 0.5;
  $("photo").style.objectPosition = `${fx * 100}% ${fy * 100}%`;
}

// ---- Touch swipe: right = keep, left = reject ----

let swipe = null;
let suppressClick = false;

function setupStagePointer() {
  const stage = $("stage");
  const movers = () => [$("photo"), $("placeholder")];

  stage.addEventListener("pointermove", (e) => {
    S.lastPointer = { x: e.clientX, y: e.clientY };
    if (S.zoomed && e.pointerType === "mouse") pan(S.lastPointer);
    if (!swipe || e.pointerId !== swipe.id) return;
    swipe.dx = e.clientX - swipe.x;
    const t = `translateX(${swipe.dx}px) rotate(${swipe.dx / 40}deg)`;
    movers().forEach((m) => (m.style.transform = t));
  });

  stage.addEventListener("pointerdown", (e) => {
    if (e.pointerType === "mouse" || S.zoomed || e.target === $("video")) return;
    swipe = { id: e.pointerId, x: e.clientX, dx: 0 };
    stage.setPointerCapture(e.pointerId);
    stage.classList.add("swiping");
  });

  const end = (e) => {
    if (!swipe || e.pointerId !== swipe.id) return;
    const { dx } = swipe;
    swipe = null;
    stage.classList.remove("swiping");
    movers().forEach((m) => (m.style.transform = ""));
    suppressClick = Math.abs(dx) > 8;
    if (Math.abs(dx) > Math.min(140, stage.clientWidth * 0.18)) decide(dx > 0 ? "keep" : "reject");
  };
  stage.addEventListener("pointerup", end);
  stage.addEventListener("pointercancel", end);

  $("photo").addEventListener("click", (e) => {
    if (suppressClick) {
      suppressClick = false;
      return;
    }
    setZoom(!S.zoomed, { x: e.clientX, y: e.clientY });
  });
}

// ---- Details panel ----

let infoToken = 0;

function toggleInfo() {
  S.info = !S.info;
  $("info-panel").hidden = !S.info;
  $("info-btn").classList.toggle("active", S.info);
  if (S.info) renderInfo();
  renderFilmstrip();
}

async function renderInfo() {
  const token = ++infoToken;
  const i = S.index;
  const item = S.items[i];
  $("info-name").textContent = basename(item.rel);
  $("info-dir").textContent = dirname(item.rel) || "(top level)";

  const rows = [];
  const add = (label, value) => value && rows.push([label, value]);
  const render = () => {
    $("info-list").replaceChildren(
      ...rows.flatMap(([k, v]) => [el("dt", { textContent: k }), el("dd", { textContent: v })]),
    );
  };

  const baseRows = () => {
    add("File size", formatBytes(item.size));
    add("Modified", new Date(item.mtime * 1000).toLocaleString());
    if (item.companions.length) add("Moves with", item.companions.map(basename).join(", "));
  };
  baseRows();
  render();

  try {
    const info = await invoke("photo_info", { gen: S.gen, index: i });
    if (token !== infoToken) return;
    rows.length = 0;
    add("Taken", info.taken);
    add("Camera", info.camera);
    add("Lens", info.lens);
    add("Exposure", [info.exposure, info.aperture, info.iso].filter(Boolean).join(" · "));
    add("Focal length", info.focal);
    if (info.width && info.height) {
      add("Dimensions", `${info.width} × ${info.height} (${((info.width * info.height) / 1e6).toFixed(1)} MP)`);
    }
    baseRows();
    render();
  } catch {}
}

// ============ Grid ============

function setView(view) {
  S.view = view;
  const grid = view === "grid";
  $("review").classList.toggle("grid-mode", grid);
  $("loupe").hidden = grid;
  $("controls").hidden = grid;
  $("grid-view").hidden = !grid;
  $("grid-btn").classList.toggle("active", grid);
  if (grid) {
    $("video").pause();
    renderGrid();
  } else {
    show(S.index);
  }
}

function matchesFilter(i) {
  const d = decisionOf(i);
  switch (S.filter) {
    case "unreviewed":
      return !d;
    case "keep":
    case "reject":
      return d === S.filter;
    default:
      return true;
  }
}

function renderGrid() {
  const c = counts();
  const tallies = { all: c.total, unreviewed: c.left, keep: c.keep, reject: c.reject };
  for (const btn of $("filters").children) {
    btn.classList.toggle("active", btn.dataset.filter === S.filter);
    btn.querySelector("span").textContent = fmt(tallies[btn.dataset.filter]);
  }
  updateProgress();

  const frag = document.createDocumentFragment();
  let current = null;
  S.items.forEach((item, i) => {
    if (!matchesFilter(i)) return;
    const tile = el(
      "div",
      { className: `tile ${decisionOf(i) ?? ""} ${i === S.index ? "current" : ""}`, title: item.rel },
      el("img", { src: thumbUrl(i), loading: "lazy", draggable: false }),
      el("span", { className: "name", textContent: basename(item.rel) }),
    );
    tile.dataset.i = i;
    if (item.kind === "video") tile.append(el("span", { className: "video-mark", textContent: "▶" }));
    if (i === S.index) current = tile;
    frag.append(tile);
  });
  if (!frag.childNodes.length) frag.append(el("div", { className: "grid-empty", textContent: "Nothing here." }));
  $("grid").replaceChildren(frag);
  current?.scrollIntoView({ block: "center" });
}

// ============ Finish ============

function openFinish() {
  const c = counts();
  const rejects = S.items.filter((it) => S.decisions.get(it.rel) === "reject");
  const bytes = rejects.reduce((sum, it) => sum + it.size, 0);
  const extras = rejects.reduce((sum, it) => sum + it.companions.length, 0);
  const body = $("finish-body");
  const actions = $("finish-actions");
  const dialog = $("finish-dialog");
  const cancel = el("button", { className: "btn", textContent: rejects.length ? "Keep reviewing" : "Close" });
  cancel.addEventListener("click", () => dialog.close());

  if (!rejects.length) {
    body.replaceChildren(
      el("p", { textContent: "Nothing is marked as a reject yet. Press ← or X on a photo to mark it." }),
    );
    actions.replaceChildren(cancel);
    dialog.showModal();
    return;
  }

  const summary = el("p");
  summary.append(
    "You've marked ",
    el("strong", { textContent: plural(rejects.length, rejects.some((it) => it.kind === "video") ? "item" : "photo") }),
    " as rejects, freeing ",
    el("strong", { textContent: formatBytes(bytes) }),
    extras ? ` (plus ${plural(extras, "Live Photo / sidecar file")} that go with them).` : ".",
  );
  const parts = [summary];
  if (c.left) {
    parts.push(el("p", { textContent: `${plural(c.left, "photo")} haven't been reviewed yet. They'll be left alone.` }));
  }
  const choice = (mode, cls, title, detail) => {
    const btn = el("button", { className: `btn choice ${cls}` }, title, el("small", { textContent: detail }));
    btn.addEventListener("click", () => applyCull(mode));
    return btn;
  };
  parts.push(
    choice("trash", "danger", "Move rejects to the Trash", "Recoverable from the Trash in your file manager."),
    choice(
      "folder",
      "",
      "Move rejects into a “_Rejected” folder",
      "Puts them in a _Rejected folder inside this one so you can double-check before deleting.",
    ),
  );
  body.replaceChildren(...parts);
  actions.replaceChildren(cancel);
  dialog.showModal();
}

async function applyCull(mode) {
  const body = $("finish-body");
  const actions = $("finish-actions");
  const dialog = $("finish-dialog");
  body.replaceChildren(el("p", { textContent: "Moving files…" }));
  actions.replaceChildren();

  let outcome;
  try {
    outcome = await saveChain.then(() => invoke("apply_cull", { gen: S.gen, mode }));
  } catch (err) {
    body.replaceChildren(el("p", { textContent: `Something went wrong: ${err}` }));
    const close = el("button", { className: "btn", textContent: "Close" });
    close.addEventListener("click", () => dialog.close());
    actions.replaceChildren(close);
    return;
  }

  const where = mode === "trash" ? "the Trash" : "the _Rejected folder";
  const summary = `Moved ${plural(outcome.items, "item")} (${formatBytes(outcome.bytes)}) to ${where}.`;
  if (outcome.failed.length) {
    body.replaceChildren(
      el("p", { textContent: summary }),
      el("p", { textContent: `${plural(outcome.failed.length, "item")} couldn't be moved and are still marked as rejects:` }),
      el("div", {
        className: "failures",
        textContent: outcome.failed.map((f) => `${f.rel}: ${f.error}`).join("\n"),
      }),
    );
    const close = el("button", { className: "btn primary", textContent: "OK" });
    close.addEventListener("click", () => dialog.close());
    actions.replaceChildren(close);
  } else {
    dialog.close();
    toast(summary);
  }
  await openFolder(S.root, { message: "Refreshing…" });
}

// ============ Keyboard ============

const DECISION_KEYS = new Set(["ArrowRight", "ArrowLeft", "p", "P", "x", "X", "Delete"]);

function onKey(e) {
  if ($("review").hidden || document.querySelector("dialog[open]")) return;
  if (e.target instanceof HTMLInputElement) return;
  const k = e.key;

  if ((e.ctrlKey || e.metaKey) && k.toLowerCase() === "z") {
    e.preventDefault();
    undo();
    return;
  }
  if (e.ctrlKey || e.metaKey || e.altKey) return;

  if (S.view === "grid") {
    if (["g", "G", "Escape"].includes(k)) {
      e.preventDefault();
      setView("loupe");
    } else if (k === "Backspace") {
      e.preventDefault();
      undo();
    }
    return;
  }

  // Holding a decision key shouldn't machine-gun through the folder.
  if (e.repeat && DECISION_KEYS.has(k)) {
    e.preventDefault();
    return;
  }

  switch (k) {
    case "ArrowRight":
    case "p":
    case "P":
      decide("keep");
      break;
    case "ArrowLeft":
    case "x":
    case "X":
    case "Delete":
      decide("reject");
      break;
    case "ArrowDown":
    case " ":
      show(S.index + 1);
      break;
    case "ArrowUp":
      show(S.index - 1);
      break;
    case "Backspace":
      undo();
      break;
    case "u":
    case "U":
      clearDecision();
      break;
    case "n":
    case "N": {
      const next = nextUnreviewed(S.index + 1);
      if (next == null) toast("Everything's been reviewed");
      else show(next);
      break;
    }
    case "z":
    case "Z":
      setZoom(!S.zoomed, S.lastPointer);
      break;
    case "g":
    case "G":
      setView("grid");
      break;
    case "i":
    case "I":
      toggleInfo();
      break;
    case "?":
      $("help-dialog").showModal();
      break;
    case "Home":
      show(0);
      break;
    case "End":
      show(S.items.length - 1);
      break;
    case "Escape":
      if (S.zoomed) setZoom(false);
      else $("done-card").hidden = true;
      break;
    default:
      return;
  }
  e.preventDefault();
}

// ============ Wiring ============

function init() {
  invoke("video_base").then((base) => (videoBase = base));
  loadOptions();
  renderRecents();

  $("open-btn").addEventListener("click", chooseFolder);
  $("opt-recursive").addEventListener("change", saveOptions);
  $("opt-videos").addEventListener("change", saveOptions);

  $("home-btn").addEventListener("click", showHome);
  $("grid-btn").addEventListener("click", () => setView(S.view === "grid" ? "loupe" : "grid"));
  $("info-btn").addEventListener("click", toggleInfo);
  $("help-btn").addEventListener("click", () => $("help-dialog").showModal());
  $("help-close").addEventListener("click", () => $("help-dialog").close());
  $("finish-btn").addEventListener("click", openFinish);

  $("keep-btn").addEventListener("click", () => decide("keep"));
  $("reject-btn").addEventListener("click", () => decide("reject"));
  $("skip-btn").addEventListener("click", () => show(S.index + 1));
  $("undo-btn").addEventListener("click", undo);

  $("done-finish").addEventListener("click", openFinish);
  $("done-rejects").addEventListener("click", () => {
    S.filter = "reject";
    setView("grid");
  });

  $("reveal-btn").addEventListener("click", () =>
    invoke("reveal", { gen: S.gen, index: S.index }).catch((e) => toast(String(e), true)),
  );
  const openExternal = () =>
    invoke("open_external", { gen: S.gen, index: S.index }).catch((e) => toast(String(e), true));
  $("external-btn").addEventListener("click", openExternal);
  $("media-error-open").addEventListener("click", openExternal);
  $("video").addEventListener("error", () => {
    if ($("video").getAttribute("src")) {
      $("media-error-text").textContent =
        "This video can't be played here (it may need extra GStreamer codecs). You can still keep or reject it.";
      $("media-error").hidden = false;
    }
  });

  $("filters").addEventListener("click", (e) => {
    const btn = e.target.closest("button");
    if (!btn) return;
    S.filter = btn.dataset.filter;
    renderGrid();
  });
  $("grid").addEventListener("click", (e) => {
    const tile = e.target.closest(".tile");
    if (!tile) return;
    S.index = Number(tile.dataset.i);
    setView("loupe");
  });

  // Buttons shouldn't keep focus, or Space would re-trigger them.
  $("review").addEventListener("click", (e) => e.target.closest("button")?.blur());

  // A thumbnail that can't be generated leaves a plain tile, not a broken-image icon.
  document.addEventListener(
    "error",
    (e) => {
      if (e.target instanceof HTMLImageElement && e.target.closest(".tile, .strip-tile")) {
        e.target.style.visibility = "hidden";
      }
    },
    true,
  );

  setupStagePointer();
  document.addEventListener("keydown", onKey);
  window.addEventListener("resize", () => !$("review").hidden && S.view === "loupe" && renderFilmstrip());
  window.addEventListener("beforeunload", rememberRecent);

  // Drop a folder (or a file inside one) anywhere on the window.
  window.__TAURI__.webview.getCurrentWebview().onDragDropEvent(({ payload }) => {
    const home = $("home");
    if (payload.type === "enter" || payload.type === "over") home.classList.add("dropping");
    else home.classList.remove("dropping");
    if (payload.type === "drop" && payload.paths?.length) {
      rememberRecent();
      openFolder(payload.paths[0]);
    }
  });
}

init();
