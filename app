"use strict";

/*
  Stream-safe Music Player
  - Loads library.json
  - Search/filter
  - Queue (playlist)
  - Player controls: play/pause, next/prev, shuffle, loop, seek, volume, mute
  - Keyboard shortcuts
*/

const el = (id) => document.getElementById(id);

const state = {
  library: [],
  filtered: [],
  queue: [],
  queueIndex: -1,
  isLoop: false,
  isShuffle: false,
  lastSearch: "",
  userGestureUnlocked: false
};

const audio = el("audio");

// UI elements
const tracksGrid = el("tracksGrid");
const libraryMeta = el("libraryMeta");
const queueList = el("queueList");

const searchInput = el("searchInput");
const playAllBtn = el("playAllBtn");
const shuffleAllBtn = el("shuffleAllBtn");
const clearQueueBtn = el("clearQueueBtn");
const saveQueueBtn = el("saveQueueBtn");

const prevBtn = el("prevBtn");
const playBtn = el("playBtn");
const nextBtn = el("nextBtn");
const loopBtn = el("loopBtn");
const shuffleBtn = el("shuffleBtn");
const seek = el("seek");
const volume = el("volume");
const muteBtn = el("muteBtn");

const npTitle = el("npTitle");
const npSub = el("npSub");
const coverBox = el("coverBox");
const timeNow = el("timeNow");
const timeTotal = el("timeTotal");

function fmtTime(sec) {
  if (!isFinite(sec) || sec < 0) return "0:00";
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

function setView(view) {
  document.querySelectorAll(".navBtn").forEach(b => b.classList.toggle("active", b.dataset.view === view));
  document.querySelectorAll(".view").forEach(v => v.classList.toggle("active", v.id === `view-${view}`));
}

function safeText(s) {
  return String(s ?? "");
}

function matchesQuery(track, q) {
  if (!q) return true;
  const hay = [
    track.title,
    track.artist,
    (track.tags || []).join(" "),
    track.license,
    track.id
  ].join(" ").toLowerCase();
  return hay.includes(q.toLowerCase());
}

function renderLibrary() {
  const total = state.library.length;
  const shown = state.filtered.length;
  libraryMeta.textContent = `${shown} shown, ${total} total${state.lastSearch ? ` (search: "${state.lastSearch}")` : ""}`;

  tracksGrid.innerHTML = "";
  state.filtered.forEach((t) => {
    const card = document.createElement("div");
    card.className = "card";

    const cover = document.createElement("div");
    cover.className = "cardCover";
    cover.textContent = safeText(t.coverText || "♫");

    const text = document.createElement("div");
    text.className = "cardText";

    const title = document.createElement("div");
    title.className = "cardTitle";
    title.textContent = safeText(t.title);

    const sub = document.createElement("div");
    sub.className = "cardSub";
    sub.textContent = `${safeText(t.artist)} · ${(t.tags || []).slice(0,3).join(", ")}`;

    const badge = document.createElement("div");
    badge.className = "badge";
    badge.textContent = safeText(t.license || "license unknown");

    text.appendChild(title);
    text.appendChild(sub);
    text.appendChild(badge);

    const actions = document.createElement("div");
    actions.className = "cardActions";

    const playNow = document.createElement("button");
    playNow.textContent = "Play";
    playNow.addEventListener("click", async () => {
      unlockByGesture();
      state.queue = [t];
      state.queueIndex = 0;
      renderQueue();
      await playAtIndex(0);
      setView("queue");
    });

    const addQueue = document.createElement("button");
    addQueue.textContent = "Add";
    addQueue.addEventListener("click", () => {
      state.queue.push(t);
      if (state.queueIndex === -1) state.queueIndex = 0;
      renderQueue();
    });

    actions.appendChild(playNow);
    actions.appendChild(addQueue);

    card.appendChild(cover);
    card.appendChild(text);
    card.appendChild(actions);

    tracksGrid.appendChild(card);
  });
}

function renderQueue() {
  queueList.innerHTML = "";
  if (state.queue.length === 0) {
    const empty = document.createElement("div");
    empty.className = "listItem";
    empty.innerHTML = `<div class="left"><div class="title">Queue is empty</div><div class="sub">Add tracks from the Library.</div></div>`;
    queueList.appendChild(empty);
    updateNowPlaying(null);
    return;
  }

  state.queue.forEach((t, idx) => {
    const item = document.createElement("div");
    item.className = "listItem";

    const left = document.createElement("div");
    left.className = "left";

    const title = document.createElement("div");
    title.className = "title";
    title.textContent = `${idx === state.queueIndex ? "▶ " : ""}${safeText(t.title)}`;

    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = `${safeText(t.artist)} · ${safeText(t.license || "")}`;

    left.appendChild(title);
    left.appendChild(sub);

    const right = document.createElement("div");
    right.className = "right";

    const playBtn = document.createElement("button");
    playBtn.textContent = "Play";
    playBtn.addEventListener("click", async () => {
      unlockByGesture();
      await playAtIndex(idx);
    });

    const upBtn = document.createElement("button");
    upBtn.textContent = "↑";
    upBtn.title = "Move up";
    upBtn.disabled = idx === 0;
    upBtn.addEventListener("click", () => {
      const tmp = state.queue[idx - 1];
      state.queue[idx - 1] = state.queue[idx];
      state.queue[idx] = tmp;
      if (state.queueIndex === idx) state.queueIndex = idx - 1;
      else if (state.queueIndex === idx - 1) state.queueIndex = idx;
      renderQueue();
    });

    const rmBtn = document.createElement("button");
    rmBtn.textContent = "Remove";
    rmBtn.addEventListener("click", () => {
      state.queue.splice(idx, 1);
      if (state.queue.length === 0) {
        state.queueIndex = -1;
        audio.pause();
        audio.src = "";
      } else if (idx < state.queueIndex) {
        state.queueIndex -= 1;
      } else if (idx === state.queueIndex) {
        state.queueIndex = Math.min(state.queueIndex, state.queue.length - 1);
      }
      renderQueue();
      updateNowPlaying(getCurrentTrack());
    });

    right.appendChild(playBtn);
    right.appendChild(upBtn);
    right.appendChild(rmBtn);

    item.appendChild(left);
    item.appendChild(right);
    queueList.appendChild(item);
  });
}

function updateNowPlaying(track) {
  if (!track) {
    npTitle.textContent = "Nothing playing";
    npSub.textContent = "Tap Play";
    coverBox.textContent = "♫";
    playBtn.textContent = "▶";
    timeNow.textContent = "0:00";
    timeTotal.textContent = "0:00";
    seek.value = 0;
    return;
  }

  npTitle.textContent = safeText(track.title);
  npSub.textContent = `${safeText(track.artist)} · ${safeText(track.license || "")}`;
  coverBox.textContent = safeText(track.coverText || "♫");
}

function getCurrentTrack() {
  if (state.queueIndex < 0 || state.queueIndex >= state.queue.length) return null;
  return state.queue[state.queueIndex];
}

function unlockByGesture() {
  state.userGestureUnlocked = true;
}

async function playAtIndex(idx) {
  if (idx < 0 || idx >= state.queue.length) return;
  state.queueIndex = idx;
  const track = getCurrentTrack();
  updateNowPlaying(track);
  renderQueue();

  audio.src = track.file;
  audio.loop = state.isLoop;

  try {
    await audio.play();
    playBtn.textContent = "⏸";
  } catch (e) {
    // Autoplay blocked, user needs to tap play
    playBtn.textContent = "▶";
  }
}

function nextIndex() {
  if (state.queue.length === 0) return -1;
  if (state.isShuffle && state.queue.length > 1) {
    let r = state.queueIndex;
    while (r === state.queueIndex) r = Math.floor(Math.random() * state.queue.length);
    return r;
  }
  return (state.queueIndex + 1) % state.queue.length;
}

function prevIndex() {
  if (state.queue.length === 0) return -1;
  if (audio.currentTime > 3) return state.queueIndex; // restart track
  return (state.queueIndex - 1 + state.queue.length) % state.queue.length;
}

// Events
playBtn.addEventListener("click", async () => {
  unlockByGesture();

  const track = getCurrentTrack();
  if (!track) {
    // If nothing queued, play filtered list
    if (state.filtered.length > 0) {
      state.queue = [...state.filtered];
      state.queueIndex = 0;
      renderQueue();
      await playAtIndex(0);
      setView("queue");
    }
    return;
  }

  if (audio.paused) {
    try { await audio.play(); playBtn.textContent = "⏸"; }
    catch { playBtn.textContent = "▶"; }
  } else {
    audio.pause();
    playBtn.textContent = "▶";
  }
});

nextBtn.addEventListener("click", async () => {
  unlockByGesture();
  const ni = nextIndex();
  if (ni !== -1) await playAtIndex(ni);
});

prevBtn.addEventListener("click", async () => {
  unlockByGesture();
  const pi = prevIndex();
  if (pi !== -1) await playAtIndex(pi);
});

loopBtn.addEventListener("click", () => {
  state.isLoop = !state.isLoop;
  audio.loop = state.isLoop;
  loopBtn.style.borderColor = state.isLoop ? "rgba(76,125,255,.65)" : "rgba(255,255,255,.12)";
});

shuffleBtn.addEventListener("click", () => {
  state.isShuffle = !state.isShuffle;
  shuffleBtn.style.borderColor = state.isShuffle ? "rgba(76,125,255,.65)" : "rgba(255,255,255,.12)";
});

seek.addEventListener("input", () => {
  if (!isFinite(audio.duration) || audio.duration <= 0) return;
  const pct = Number(seek.value) / 1000;
  audio.currentTime = pct * audio.duration;
});

volume.addEventListener("input", () => {
  audio.volume = Number(volume.value);
  audio.muted = false;
  muteBtn.textContent = "Mute";
});

muteBtn.addEventListener("click", () => {
  audio.muted = !audio.muted;
  muteBtn.textContent = audio.muted ? "Unmute" : "Mute";
});

audio.addEventListener("timeupdate", () => {
  timeNow.textContent = fmtTime(audio.currentTime);
  timeTotal.textContent = fmtTime(audio.duration);
  if (isFinite(audio.duration) && audio.duration > 0) {
    seek.value = Math.floor((audio.currentTime / audio.duration) * 1000);
  }
});

audio.addEventListener("ended", async () => {
  if (state.isLoop) return;
  const ni = nextIndex();
  if (ni !== -1) await playAtIndex(ni);
});

searchInput.addEventListener("input", () => {
  const q = searchInput.value.trim();
  state.lastSearch = q;
  state.filtered = state.library.filter(t => matchesQuery(t, q));
  renderLibrary();
});

playAllBtn.addEventListener("click", async () => {
  unlockByGesture();
  if (state.filtered.length === 0) return;
  state.queue = [...state.filtered];
  state.queueIndex = 0;
  renderQueue();
  await playAtIndex(0);
  setView("queue");
});

shuffleAllBtn.addEventListener("click", async () => {
  unlockByGesture();
  if (state.filtered.length === 0) return;
  state.queue = [...state.filtered];
  // Fisher-Yates shuffle
  for (let i = state.queue.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [state.queue[i], state.queue[j]] = [state.queue[j], state.queue[i]];
  }
  state.queueIndex = 0;
  renderQueue();
  await playAtIndex(0);
  setView("queue");
});

clearQueueBtn?.addEventListener("click", () => {
  state.queue = [];
  state.queueIndex = -1;
  audio.pause();
  audio.src = "";
  renderQueue();
});

saveQueueBtn?.addEventListener("click", () => {
  const payload = {
    exportedAt: new Date().toISOString(),
    queue: state.queue.map(t => ({ id: t.id, title: t.title, artist: t.artist, file: t.file, license: t.license, sourceUrl: t.sourceUrl }))
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "queue-export.json";
  a.click();
  URL.revokeObjectURL(a.href);
});

// Sidebar navigation
document.querySelectorAll(".navBtn").forEach(btn => {
  btn.addEventListener("click", () => setView(btn.dataset.view));
});

// Keyboard shortcuts
document.addEventListener("keydown", async (e) => {
  const activeTag = document.activeElement?.tagName?.toLowerCase();
  const typing = activeTag === "input" || activeTag === "textarea";

  if (e.key === "/" && !typing) {
    e.preventDefault();
    searchInput.focus();
    return;
  }

  if (typing) return;

  if (e.key === " "){ // space
    e.preventDefault();
    playBtn.click();
  } else if (e.key.toLowerCase() === "n") {
    nextBtn.click();
  } else if (e.key.toLowerCase() === "p") {
    prevBtn.click();
  }
});

// Load library
async function init() {
  try {
    const res = await fetch("assets/library.json", { cache: "no-store" });
    const data = await res.json();
    state.library = Array.isArray(data.tracks) ? data.tracks : [];
    // Basic validation
    state.library = state.library.filter(t => t && t.id && t.title && t.file);
    state.filtered = [...state.library];
    renderLibrary();
    renderQueue();
  } catch (e) {
    libraryMeta.textContent = "Failed to load library.json. Check file paths.";
  }
}

init();
