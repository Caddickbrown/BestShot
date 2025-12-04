const projectsList = document.getElementById("projects-list");
const newProjectForm = document.getElementById("new-project-form");
const projectNameInput = document.getElementById("project-name");
const projectDescriptionInput = document.getElementById("project-description-input");
const refreshProjectsBtn = document.getElementById("refresh-projects");
const workspaceTitle = document.getElementById("workspace-title");
const workspaceMeta = document.getElementById("workspace-meta");
const dropZone = document.getElementById("drop-zone");
const dropZoneDefault = dropZone.innerHTML;
const browseFilesBtn = document.getElementById("browse-files");
const fileInput = document.getElementById("file-input");
const saveOrderBtn = document.getElementById("save-order");
const imagesGrid = document.getElementById("images-grid");
const imageTemplate = document.getElementById("image-card-template");
const videoTemplate = document.getElementById("video-card-template");
const projectDescriptionForm = document.getElementById("project-description-form");
const projectDescriptionField = document.getElementById("project-description");
const projectDescriptionStatus = document.getElementById("project-description-status");
const saveDescriptionBtn = document.getElementById("save-description");
const viewModeButtons = document.querySelectorAll("[data-view-mode]");
const mediaFilterButtons = document.querySelectorAll("[data-media-filter]");
const searchInput = document.getElementById("search-input");
const clearSearchBtn = document.getElementById("clear-search");

// Video modal elements
const videoModal = document.getElementById("video-modal");
const modalVideo = document.getElementById("modal-video");
const modalVideoName = document.getElementById("modal-video-name");
const modalBackdrop = videoModal.querySelector(".video-modal__backdrop");
const modalCloseBtn = videoModal.querySelector(".video-modal__close");

const state = {
  projects: [],
  currentProject: null,
  images: [],
  description: "",
  viewMode: "rank",
  mediaFilter: "all", // 'all', 'photos', or 'videos'
  searchQuery: "",
};

// Touch drag-and-drop state
let touchDragState = null;

// ============ URL State Persistence ============
// Enables resuming on another device by sharing/bookmarking the URL

function getStateFromURL() {
  const params = new URLSearchParams(window.location.search);
  return {
    project: params.get("project"),
    view: params.get("view"),
    media: params.get("media"),
  };
}

function updateURL() {
  const params = new URLSearchParams();
  if (state.currentProject) {
    params.set("project", state.currentProject);
  }
  if (state.viewMode && state.viewMode !== "rank") {
    params.set("view", state.viewMode);
  }
  if (state.mediaFilter && state.mediaFilter !== "all") {
    params.set("media", state.mediaFilter);
  }
  const newURL = params.toString()
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;
  window.history.replaceState({}, "", newURL);
}

function restoreStateFromURL() {
  const urlState = getStateFromURL();
  if (urlState.view === "gallery" || urlState.view === "rank") {
    state.viewMode = urlState.view;
    viewModeButtons.forEach((button) => {
      button.classList.toggle("active", button.dataset.viewMode === state.viewMode);
    });
  }
  if (urlState.media === "photos" || urlState.media === "videos" || urlState.media === "all") {
    state.mediaFilter = urlState.media;
    mediaFilterButtons.forEach((button) => {
      button.classList.toggle("active", button.dataset.mediaFilter === state.mediaFilter);
    });
  }
  return urlState.project;
}

async function fetchProjects(initialProjectFromURL = null) {
  const res = await fetch("/api/projects");
  if (!res.ok) {
    console.error("Failed to load projects");
    return;
  }
  const data = await res.json();
  state.projects = data.projects;
  renderProjects();

  if (!state.projects.length) {
    state.currentProject = null;
    state.images = [];
    disableWorkspace();
    updateURL();
    return;
  }

  // Priority: URL param > current selection > first project
  let targetProject = null;
  if (initialProjectFromURL && state.projects.some((p) => p.name === initialProjectFromURL)) {
    targetProject = initialProjectFromURL;
  } else if (state.currentProject && state.projects.some((p) => p.name === state.currentProject)) {
    targetProject = state.currentProject;
  } else {
    targetProject = state.projects[0].name;
  }

  if (targetProject !== state.currentProject) {
    await selectProject(targetProject);
  }
}

function renderProjects() {
  projectsList.innerHTML = "";
  if (!state.projects.length) {
    const empty = document.createElement("li");
    empty.textContent = "No projects yet";
    empty.style.textAlign = "center";
    empty.style.opacity = "0.6";
    projectsList.appendChild(empty);
    return;
  }

  state.projects.forEach((project) => {
    const li = document.createElement("li");
    const title = document.createElement("h3");
    title.textContent = project.name;
    const details = document.createElement("small");
    const parts = [];
    if (project.imageCount > 0) {
      parts.push(`${project.imageCount} photo${project.imageCount === 1 ? "" : "s"}`);
    }
    if (project.videoCount > 0) {
      parts.push(`${project.videoCount} video${project.videoCount === 1 ? "" : "s"}`);
    }
    details.textContent = parts.length ? parts.join(", ") : "Empty";
    const desc = document.createElement("p");
    desc.textContent = project.description || "No description yet.";

    li.append(title, details, desc);

    if (state.currentProject === project.name) {
      li.classList.add("active");
    }

    li.addEventListener("click", () => selectProject(project.name));
    projectsList.appendChild(li);
  });
}

async function selectProject(name) {
  state.currentProject = name;
  renderProjects();
  updateURL();
  await loadProjectState();
}

async function loadProjectState() {
  if (!state.currentProject) {
    disableWorkspace();
    return;
  }
  const url = `/api/projects/${encodeURIComponent(state.currentProject)}/images?media=${state.mediaFilter}`;
  const res = await fetch(url);
  if (!res.ok) {
    alert("Unable to load project");
    return;
  }
  const data = await res.json();
  state.images = data.images;
  state.description = data.description || "";
  workspaceTitle.textContent = data.project;
  
  // Update meta text based on media types
  const imageCount = state.images.filter((m) => m.type === "image").length;
  const videoCount = state.images.filter((m) => m.type === "video").length;
  const parts = [];
  if (imageCount > 0) parts.push(`${imageCount} photo${imageCount === 1 ? "" : "s"}`);
  if (videoCount > 0) parts.push(`${videoCount} video${videoCount === 1 ? "" : "s"}`);
  workspaceMeta.textContent = parts.length ? parts.join(", ") : "No media";
  
  projectDescriptionField.value = state.description;
  projectDescriptionStatus.textContent = state.description ? "Saved" : "No note";
  enableWorkspace();
  renderImages();
}

function getFilteredImages() {
  if (!state.searchQuery.trim()) {
    return state.images;
  }
  const query = state.searchQuery.toLowerCase().trim();
  return state.images.filter((media) => {
    // Match filename
    if (media.name.toLowerCase().includes(query)) {
      return true;
    }
    // Match tags
    if (media.tags && media.tags.some((tag) => tag.toLowerCase().includes(query))) {
      return true;
    }
    return false;
  });
}

function renderImages() {
  imagesGrid.innerHTML = "";
  imagesGrid.classList.toggle("gallery", state.viewMode === "gallery");

  const filteredImages = getFilteredImages();

  if (!state.images.length) {
    const empty = document.createElement("p");
    let emptyText = "Select a project to begin.";
    if (state.currentProject) {
      if (state.mediaFilter === "photos") {
        emptyText = "No photos yet. Drop them into the project folder.";
      } else if (state.mediaFilter === "videos") {
        emptyText = "No videos yet. Drop them into the project folder.";
      } else {
        emptyText = "No media yet. Drop files into the project folder.";
      }
    }
    empty.textContent = emptyText;
    empty.classList.add("muted");
    imagesGrid.appendChild(empty);
    updateActionStates();
    return;
  }

  if (!filteredImages.length && state.searchQuery) {
    const empty = document.createElement("p");
    empty.textContent = `No results for "${state.searchQuery}"`;
    empty.classList.add("muted");
    imagesGrid.appendChild(empty);
    updateActionStates();
    return;
  }

  filteredImages.forEach((media, index) => {
    const isVideo = media.type === "video";
    const template = isVideo ? videoTemplate : imageTemplate;
    const card = template.content.firstElementChild.cloneNode(true);
    const originalIndex = state.images.indexOf(media);
    card.dataset.index = originalIndex;
    card.dataset.name = media.name;
    card.dataset.mediaType = media.type;
    card.classList.toggle("is-gallery", state.viewMode === "gallery");
    
    const rank = card.querySelector(".rank-pill");
    rank.textContent = `#${originalIndex + 1}`;
    card.querySelector(".filename").textContent = media.name;

    if (isVideo) {
      const video = card.querySelector("video");
      video.src = `${media.url}?v=${Date.now()}`;
      // Load first frame as thumbnail
      video.addEventListener("loadeddata", () => {
        video.currentTime = 0.1;
      });
      
      const playButton = card.querySelector(".play-button");
      playButton.addEventListener("click", (event) => {
        event.stopPropagation();
        openVideoModal(media);
      });
    } else {
      const img = card.querySelector("img");
      img.src = `${media.url}?v=${Date.now()}`;
      img.alt = media.name;
    }

    // Render tags
    renderCardTags(card, media);

    card.draggable = state.viewMode === "rank" && !state.searchQuery;
    if (state.viewMode === "rank" && !state.searchQuery) {
      // Mouse drag-and-drop events
      card.addEventListener("dragstart", (event) => {
        event.dataTransfer.effectAllowed = "move";
        card.classList.add("dragging");
        card.dataset.dragIndex = originalIndex;
      });

      card.addEventListener("dragend", () => {
        card.classList.remove("dragging");
      });

      card.addEventListener("dragover", (event) => {
        event.preventDefault();
        card.classList.add("over");
      });

      card.addEventListener("dragleave", () => card.classList.remove("over"));

      card.addEventListener("drop", (event) => {
        event.preventDefault();
        card.classList.remove("over");
        const dragged = document.querySelector(".image-card.dragging");
        if (!dragged) return;
        const from = Number(dragged.dataset.dragIndex);
        const to = Number(card.dataset.index);
        reorderImages(from, to);
      });

      // Touch drag-and-drop events (for mobile/tablet)
      card.addEventListener("touchstart", handleTouchStart, { passive: false });
      card.addEventListener("touchmove", handleTouchMove, { passive: false });
      card.addEventListener("touchend", handleTouchEnd, { passive: false });
    }

    imagesGrid.appendChild(card);
  });

  updateActionStates();
}

function renderCardTags(card, media) {
  const tagsContainer = card.querySelector(".tags-list");
  const addTagBtn = card.querySelector(".add-tag-btn");
  const tagInputWrapper = card.querySelector(".tag-input-wrapper");
  const tagInput = card.querySelector(".tag-input");

  // Only show tags UI in gallery mode
  const tagsSection = card.querySelector(".image-card__tags");
  if (state.viewMode !== "gallery") {
    tagsSection.hidden = true;
    return;
  }
  tagsSection.hidden = false;

  // Render existing tags
  tagsContainer.innerHTML = "";
  if (media.tags && media.tags.length) {
    media.tags.forEach((tag) => {
      const tagEl = document.createElement("span");
      tagEl.className = "tag";
      tagEl.innerHTML = `${escapeHtml(tag)}<button class="tag-remove" aria-label="Remove tag">&times;</button>`;
      tagEl.querySelector(".tag-remove").addEventListener("click", (e) => {
        e.stopPropagation();
        removeTag(media.name, tag);
      });
      tagsContainer.appendChild(tagEl);
    });
  }

  // Add tag button
  addTagBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    tagInputWrapper.hidden = false;
    addTagBtn.hidden = true;
    tagInput.focus();
  });

  // Tag input handling
  tagInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      const newTag = tagInput.value.trim();
      if (newTag) {
        addTag(media.name, newTag);
      }
      tagInput.value = "";
      tagInputWrapper.hidden = true;
      addTagBtn.hidden = false;
    } else if (e.key === "Escape") {
      tagInput.value = "";
      tagInputWrapper.hidden = true;
      addTagBtn.hidden = false;
    }
  });

  tagInput.addEventListener("blur", () => {
    setTimeout(() => {
      tagInput.value = "";
      tagInputWrapper.hidden = true;
      addTagBtn.hidden = false;
    }, 150);
  });
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

async function addTag(filename, tag) {
  if (!state.currentProject) return;
  const media = state.images.find((m) => m.name === filename);
  if (!media) return;

  const currentTags = media.tags || [];
  const normalizedTag = tag.trim().toLowerCase();
  if (currentTags.includes(normalizedTag)) return;

  const newTags = [...currentTags, normalizedTag];
  await updateMediaTags(filename, newTags);
}

async function removeTag(filename, tag) {
  if (!state.currentProject) return;
  const media = state.images.find((m) => m.name === filename);
  if (!media) return;

  const currentTags = media.tags || [];
  const newTags = currentTags.filter((t) => t !== tag);
  await updateMediaTags(filename, newTags);
}

async function updateMediaTags(filename, tags) {
  if (!state.currentProject) return;

  const res = await fetch(
    `/api/projects/${encodeURIComponent(state.currentProject)}/media/${encodeURIComponent(filename)}/tags`,
    {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ tags }),
    }
  );

  if (!res.ok) {
    alert("Failed to update tags");
    return;
  }

  const data = await res.json();
  // Update local state
  const media = state.images.find((m) => m.name === filename);
  if (media) {
    media.tags = data.tags;
  }
  renderImages();
}

function reorderImages(from, to) {
  if (state.viewMode !== "rank") return;
  if (Number.isNaN(from) || Number.isNaN(to) || from === to) {
    return;
  }
  const [moved] = state.images.splice(from, 1);
  state.images.splice(to, 0, moved);
  renderImages();
}

// ============ Touch Drag-and-Drop Support ============
// Enables ranking on mobile devices (phones/tablets)

function handleTouchStart(event) {
  if (state.viewMode !== "rank") return;

  const card = event.currentTarget;
  const touch = event.touches[0];

  // Allow some time to determine if this is a scroll or drag
  touchDragState = {
    card: card,
    startX: touch.clientX,
    startY: touch.clientY,
    currentX: touch.clientX,
    currentY: touch.clientY,
    index: Number(card.dataset.index),
    isDragging: false,
    clone: null,
    scrollThreshold: 10,
  };
}

function handleTouchMove(event) {
  if (!touchDragState) return;

  const touch = event.touches[0];
  const deltaX = Math.abs(touch.clientX - touchDragState.startX);
  const deltaY = Math.abs(touch.clientY - touchDragState.startY);

  // Start dragging after moving beyond threshold
  if (!touchDragState.isDragging) {
    if (deltaX > touchDragState.scrollThreshold || deltaY > touchDragState.scrollThreshold) {
      touchDragState.isDragging = true;
      touchDragState.card.classList.add("dragging");

      // Create a visual clone that follows the finger
      const rect = touchDragState.card.getBoundingClientRect();
      const clone = touchDragState.card.cloneNode(true);
      clone.classList.add("touch-drag-clone");
      clone.style.cssText = `
        position: fixed;
        width: ${rect.width}px;
        left: ${rect.left}px;
        top: ${rect.top}px;
        pointer-events: none;
        z-index: 1000;
        opacity: 0.9;
        transform: scale(1.05);
        box-shadow: 0 10px 40px rgba(0,0,0,0.4);
      `;
      document.body.appendChild(clone);
      touchDragState.clone = clone;
      touchDragState.offsetX = touch.clientX - rect.left;
      touchDragState.offsetY = touch.clientY - rect.top;
    }
  }

  if (touchDragState.isDragging) {
    event.preventDefault(); // Prevent scrolling while dragging

    touchDragState.currentX = touch.clientX;
    touchDragState.currentY = touch.clientY;

    // Move the clone
    if (touchDragState.clone) {
      touchDragState.clone.style.left = `${touch.clientX - touchDragState.offsetX}px`;
      touchDragState.clone.style.top = `${touch.clientY - touchDragState.offsetY}px`;
    }

    // Highlight the card under the touch point
    const allCards = imagesGrid.querySelectorAll(".image-card");
    allCards.forEach((c) => c.classList.remove("over"));

    const elementBelow = document.elementFromPoint(touch.clientX, touch.clientY);
    if (elementBelow) {
      const cardBelow = elementBelow.closest(".image-card");
      if (cardBelow && cardBelow !== touchDragState.card) {
        cardBelow.classList.add("over");
      }
    }
  }
}

function handleTouchEnd(event) {
  if (!touchDragState) return;

  const { card, isDragging, clone, index } = touchDragState;

  // Clean up the clone
  if (clone) {
    clone.remove();
  }

  card.classList.remove("dragging");

  if (isDragging) {
    // Find the card we dropped on
    const allCards = imagesGrid.querySelectorAll(".image-card");
    allCards.forEach((c) => c.classList.remove("over"));

    const elementBelow = document.elementFromPoint(
      touchDragState.currentX,
      touchDragState.currentY
    );

    if (elementBelow) {
      const cardBelow = elementBelow.closest(".image-card");
      if (cardBelow && cardBelow !== card) {
        const toIndex = Number(cardBelow.dataset.index);
        reorderImages(index, toIndex);
      }
    }
  }

  touchDragState = null;
}

function disableWorkspace() {
  dropZone.classList.add("disabled");
  dropZone.innerHTML = "<p>Select a project to start.</p>";
  workspaceTitle.textContent = "Select a project";
  workspaceMeta.textContent = "";
  projectDescriptionField.value = "";
  projectDescriptionField.disabled = true;
  saveDescriptionBtn.disabled = true;
  projectDescriptionStatus.textContent = "Idle";
  state.images = [];
  state.description = "";
  updateActionStates();
}

function enableWorkspace() {
  dropZone.classList.remove("disabled");
  dropZone.innerHTML = dropZoneDefault;
  projectDescriptionField.disabled = false;
  saveDescriptionBtn.disabled = false;
  updateActionStates();
}

function updateActionStates() {
  const hasProject = Boolean(state.currentProject);
  browseFilesBtn.disabled = !hasProject;
  saveOrderBtn.disabled = !hasProject || state.viewMode !== "rank" || state.images.length === 0;
  saveDescriptionBtn.disabled = !hasProject;
  projectDescriptionField.disabled = !hasProject;
}

async function createProject(name, description) {
  const res = await fetch("/api/projects", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, description }),
  });
  if (!res.ok) {
    const error = await res.text();
    alert(error || "Failed to create project");
    return;
  }
  const created = await res.json();
  projectNameInput.value = "";
  projectDescriptionInput.value = "";
  await fetchProjects();
  await selectProject(created.name);
}

async function uploadFiles(files) {
  if (!state.currentProject || !files.length) return;

  const formData = new FormData();
  [...files].forEach((file) => formData.append("files", file));

  const res = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}/upload`, {
    method: "POST",
    body: formData,
  });

  if (!res.ok) {
    alert("Upload failed. Make sure the files are supported images.");
    return;
  }

  await loadProjectState();
  await fetchProjects();
}

async function saveOrder() {
  if (!state.currentProject) return;
  const order = state.images.map((img) => img.name);
  const res = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}/rank`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ order }),
  });

  if (!res.ok) {
    alert("Failed to save ranking");
    return;
  }

  saveOrderBtn.textContent = "Saved";
  setTimeout(() => {
    saveOrderBtn.textContent = "Save order";
  }, 1600);
}

async function saveDescription(event) {
  event.preventDefault();
  if (!state.currentProject) return;
  const description = projectDescriptionField.value.trim();
  projectDescriptionStatus.textContent = "Saving...";
  saveDescriptionBtn.disabled = true;
  const res = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ description }),
  });
  if (!res.ok) {
    projectDescriptionStatus.textContent = "Error";
    saveDescriptionBtn.disabled = false;
    alert("Could not save description");
    return;
  }
  state.description = description;
  projectDescriptionStatus.textContent = description ? "Saved" : "No note";
  saveDescriptionBtn.disabled = false;
  await fetchProjects();
  updateActionStates();
}

function setViewMode(mode) {
  if (state.viewMode === mode) return;
  state.viewMode = mode;
  viewModeButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.viewMode === state.viewMode);
  });
  updateURL();
  renderImages();
}

async function setMediaFilter(filter) {
  if (state.mediaFilter === filter) return;
  state.mediaFilter = filter;
  mediaFilterButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.mediaFilter === state.mediaFilter);
  });
  updateURL();
  await loadProjectState();
}

// ============ Video Modal Functions ============

function openVideoModal(media) {
  modalVideo.src = media.url;
  modalVideoName.textContent = media.name;
  videoModal.hidden = false;
  document.body.style.overflow = "hidden";
  modalVideo.play();
}

function closeVideoModal() {
  modalVideo.pause();
  modalVideo.src = "";
  videoModal.hidden = true;
  document.body.style.overflow = "";
}

// Video modal event listeners
modalCloseBtn.addEventListener("click", closeVideoModal);
modalBackdrop.addEventListener("click", closeVideoModal);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !videoModal.hidden) {
    closeVideoModal();
  }
});

newProjectForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const name = projectNameInput.value.trim();
  if (!name) return;
  await createProject(name, projectDescriptionInput.value.trim());
});

projectDescriptionForm.addEventListener("submit", saveDescription);

refreshProjectsBtn.addEventListener("click", fetchProjects);

viewModeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const mode = button.dataset.viewMode;
    if (mode) {
      setViewMode(mode);
    }
  });
});

mediaFilterButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const filter = button.dataset.mediaFilter;
    if (filter) {
      setMediaFilter(filter);
    }
  });
});

// Search functionality
searchInput.addEventListener("input", () => {
  state.searchQuery = searchInput.value;
  clearSearchBtn.hidden = !state.searchQuery;
  renderImages();
});

searchInput.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    searchInput.value = "";
    state.searchQuery = "";
    clearSearchBtn.hidden = true;
    renderImages();
  }
});

clearSearchBtn.addEventListener("click", () => {
  searchInput.value = "";
  state.searchQuery = "";
  clearSearchBtn.hidden = true;
  renderImages();
});

browseFilesBtn.addEventListener("click", () => fileInput.click());

fileInput.addEventListener("change", () => {
  if (fileInput.files.length) {
    uploadFiles(fileInput.files);
    fileInput.value = "";
  }
});

saveOrderBtn.addEventListener("click", () => {
  if (!state.currentProject) return;
  saveOrder();
});

dropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  if (dropZone.classList.contains("disabled")) return;
  dropZone.classList.add("over");
});

dropZone.addEventListener("dragleave", () => dropZone.classList.remove("over"));

dropZone.addEventListener("drop", (event) => {
  event.preventDefault();
  dropZone.classList.remove("over");
  if (!state.currentProject) return;
  const { files } = event.dataTransfer;
  uploadFiles(files);
});

// Initialize app with URL state restoration
const initialProject = restoreStateFromURL();
disableWorkspace();
updateActionStates();
fetchProjects(initialProject);

// Handle browser back/forward navigation
window.addEventListener("popstate", () => {
  const urlState = getStateFromURL();
  if (urlState.project && urlState.project !== state.currentProject) {
    selectProject(urlState.project);
  }
  if (urlState.view && urlState.view !== state.viewMode) {
    setViewMode(urlState.view);
  }
  if (urlState.media && urlState.media !== state.mediaFilter) {
    setMediaFilter(urlState.media);
  }
});
