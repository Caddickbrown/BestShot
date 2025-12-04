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
const deleteProjectBtn = document.getElementById("delete-project");
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

// Delete modal elements
const deleteModal = document.getElementById("delete-modal");
const deleteProjectName = document.getElementById("delete-project-name");
const confirmDeleteBtn = document.getElementById("confirm-delete");
const cancelDeleteBtn = document.getElementById("cancel-delete");
const deleteBackdrop = deleteModal.querySelector(".delete-modal__backdrop");

// Media viewer modal elements
const mediaViewerModal = document.getElementById("media-viewer-modal");
const viewerImage = document.getElementById("viewer-image");
const viewerVideo = document.getElementById("viewer-video");
const viewerFilename = document.getElementById("viewer-filename");
const viewerTagsList = document.getElementById("viewer-tags-list");
const viewerTagInput = document.getElementById("viewer-tag-input");
const viewerTagInputWrapper = document.getElementById("viewer-tag-input-wrapper");
const viewerAddTagBtn = document.getElementById("viewer-add-tag-btn");
const viewerCloseBtn = mediaViewerModal.querySelector(".media-viewer-modal__close");
const viewerBackdrop = mediaViewerModal.querySelector(".media-viewer-modal__backdrop");
const viewerPrevBtn = mediaViewerModal.querySelector(".media-viewer-modal__prev");
const viewerNextBtn = mediaViewerModal.querySelector(".media-viewer-modal__next");

// Comparison mode elements
const comparisonMode = document.getElementById("comparison-mode");
const comparisonProgress = document.getElementById("comparison-progress");
const exitComparisonBtn = document.getElementById("exit-comparison");
const compareLeft = document.getElementById("compare-left");
const compareRight = document.getElementById("compare-right");
const comparisonSkipBtn = document.getElementById("comparison-skip");

// Comparison results elements
const comparisonResults = document.getElementById("comparison-results");
const resultsList = document.getElementById("results-list");
const applyRankingBtn = document.getElementById("apply-ranking");
const discardRankingBtn = document.getElementById("discard-ranking");
const resultsBackdrop = comparisonResults.querySelector(".comparison-results__backdrop");

const state = {
  projects: [],
  currentProject: null,
  images: [],
  description: "",
  viewMode: "rank",
  mediaFilter: "all", // 'all', 'photos', or 'videos'
  searchQuery: "",
  viewerIndex: -1, // Current index in fullscreen viewer
  comparison: null, // Comparison mode state
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
        if (state.viewMode === "gallery") {
          openMediaViewer(index);
        } else {
          openVideoModal(media);
        }
      });
    } else {
      const img = card.querySelector("img");
      img.src = `${media.url}?v=${Date.now()}`;
      img.alt = media.name;
    }

    // Click handler for gallery mode fullscreen view
    if (state.viewMode === "gallery") {
      card.style.cursor = "pointer";
      card.addEventListener("click", (event) => {
        // Don't open viewer if clicking on tag controls
        if (event.target.closest(".image-card__tags")) return;
        openMediaViewer(index);
      });
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
  deleteProjectBtn.disabled = !hasProject;
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

// ============ Delete Project Functions ============

function openDeleteModal() {
  if (!state.currentProject) return;
  deleteProjectName.textContent = state.currentProject;
  deleteModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeDeleteModal() {
  deleteModal.hidden = true;
  document.body.style.overflow = "";
}

async function deleteProject() {
  if (!state.currentProject) return;
  const res = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}`, {
    method: "DELETE",
  });
  if (!res.ok) {
    alert("Failed to delete project");
    return;
  }
  closeDeleteModal();
  state.currentProject = null;
  await fetchProjects();
}

deleteProjectBtn.addEventListener("click", openDeleteModal);
confirmDeleteBtn.addEventListener("click", deleteProject);
cancelDeleteBtn.addEventListener("click", closeDeleteModal);
deleteBackdrop.addEventListener("click", closeDeleteModal);

// ============ Media Viewer Functions (Fullscreen Gallery) ============

function openMediaViewer(index) {
  const filteredImages = getFilteredImages();
  if (index < 0 || index >= filteredImages.length) return;
  
  state.viewerIndex = index;
  const media = filteredImages[index];
  
  viewerFilename.textContent = media.name;
  
  if (media.type === "video") {
    viewerImage.hidden = true;
    viewerVideo.hidden = false;
    viewerVideo.src = media.url;
  } else {
    viewerVideo.hidden = true;
    viewerImage.hidden = false;
    viewerImage.src = media.url;
    viewerImage.alt = media.name;
  }
  
  renderViewerTags(media);
  
  mediaViewerModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeMediaViewer() {
  viewerVideo.pause();
  viewerVideo.src = "";
  viewerImage.src = "";
  mediaViewerModal.hidden = true;
  document.body.style.overflow = "";
  state.viewerIndex = -1;
}

function navigateViewer(direction) {
  const filteredImages = getFilteredImages();
  let newIndex = state.viewerIndex + direction;
  
  if (newIndex < 0) newIndex = filteredImages.length - 1;
  if (newIndex >= filteredImages.length) newIndex = 0;
  
  openMediaViewer(newIndex);
}

function renderViewerTags(media) {
  viewerTagsList.innerHTML = "";
  if (media.tags && media.tags.length) {
    media.tags.forEach((tag) => {
      const tagEl = document.createElement("span");
      tagEl.className = "tag";
      tagEl.innerHTML = `${escapeHtml(tag)}<button class="tag-remove" aria-label="Remove tag">&times;</button>`;
      tagEl.querySelector(".tag-remove").addEventListener("click", (e) => {
        e.stopPropagation();
        removeViewerTag(media.name, tag);
      });
      viewerTagsList.appendChild(tagEl);
    });
  }
}

async function addViewerTag(filename, tag) {
  if (!state.currentProject) return;
  const media = state.images.find((m) => m.name === filename);
  if (!media) return;
  
  const currentTags = media.tags || [];
  const normalizedTag = tag.trim().toLowerCase();
  if (currentTags.includes(normalizedTag)) return;
  
  const newTags = [...currentTags, normalizedTag];
  await updateMediaTags(filename, newTags);
  
  // Re-render viewer tags
  const updatedMedia = state.images.find((m) => m.name === filename);
  if (updatedMedia) renderViewerTags(updatedMedia);
}

async function removeViewerTag(filename, tag) {
  if (!state.currentProject) return;
  const media = state.images.find((m) => m.name === filename);
  if (!media) return;
  
  const currentTags = media.tags || [];
  const newTags = currentTags.filter((t) => t !== tag);
  await updateMediaTags(filename, newTags);
  
  // Re-render viewer tags
  const updatedMedia = state.images.find((m) => m.name === filename);
  if (updatedMedia) renderViewerTags(updatedMedia);
}

viewerCloseBtn.addEventListener("click", closeMediaViewer);
viewerBackdrop.addEventListener("click", closeMediaViewer);
viewerPrevBtn.addEventListener("click", () => navigateViewer(-1));
viewerNextBtn.addEventListener("click", () => navigateViewer(1));

viewerAddTagBtn.addEventListener("click", (e) => {
  e.stopPropagation();
  viewerTagInputWrapper.hidden = false;
  viewerAddTagBtn.hidden = true;
  viewerTagInput.focus();
});

viewerTagInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    const filteredImages = getFilteredImages();
    const media = filteredImages[state.viewerIndex];
    if (media && viewerTagInput.value.trim()) {
      addViewerTag(media.name, viewerTagInput.value.trim());
    }
    viewerTagInput.value = "";
    viewerTagInputWrapper.hidden = true;
    viewerAddTagBtn.hidden = false;
  } else if (e.key === "Escape") {
    viewerTagInput.value = "";
    viewerTagInputWrapper.hidden = true;
    viewerAddTagBtn.hidden = false;
  }
});

viewerTagInput.addEventListener("blur", () => {
  setTimeout(() => {
    viewerTagInput.value = "";
    viewerTagInputWrapper.hidden = true;
    viewerAddTagBtn.hidden = false;
  }, 150);
});

// ============ Comparison Mode Functions ============

function generatePairs(items) {
  // Generate all unique pairs for comparison
  const pairs = [];
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      pairs.push([items[i], items[j]]);
    }
  }
  // Shuffle pairs for variety
  for (let i = pairs.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pairs[i], pairs[j]] = [pairs[j], pairs[i]];
  }
  return pairs;
}

function startComparisonMode() {
  if (state.images.length < 2) {
    alert("Need at least 2 images to start comparison mode");
    return;
  }
  
  // Initialize comparison state with transitive inference tracking
  const scores = {};
  const beatsMap = {}; // beatsMap[A] = Set of items that A beats (directly or transitively)
  const losesTo = {}; // losesTo[A] = Set of items that beat A (directly or transitively)
  
  state.images.forEach((img) => {
    scores[img.name] = 0;
    beatsMap[img.name] = new Set();
    losesTo[img.name] = new Set();
  });
  
  const allPairs = generatePairs([...state.images]);
  
  state.comparison = {
    allPairs,
    currentPairIndex: 0,
    scores,
    beatsMap,
    losesTo,
    comparisonsAsked: 0,
    comparisonsSkipped: 0,
  };
  
  comparisonMode.hidden = false;
  document.body.style.overflow = "hidden";
  
  showCurrentPair();
}

// Check if the relationship between two items is already known (through transitivity)
function isRelationshipKnown(itemA, itemB) {
  if (!state.comparison) return false;
  const { beatsMap } = state.comparison;
  // Known if A beats B or B beats A
  return beatsMap[itemA.name].has(itemB.name) || beatsMap[itemB.name].has(itemA.name);
}

// Record that winner beats loser, and propagate transitively
function recordWin(winnerName, loserName) {
  if (!state.comparison) return;
  const { beatsMap, losesTo, scores } = state.comparison;
  
  // If already known, skip
  if (beatsMap[winnerName].has(loserName)) return;
  
  // Direct win
  beatsMap[winnerName].add(loserName);
  losesTo[loserName].add(winnerName);
  scores[winnerName]++;
  
  // Transitive propagation:
  // 1. Winner also beats everything that loser beats
  for (const item of beatsMap[loserName]) {
    if (!beatsMap[winnerName].has(item)) {
      beatsMap[winnerName].add(item);
      losesTo[item].add(winnerName);
      scores[winnerName]++;
      state.comparison.comparisonsSkipped++;
    }
  }
  
  // 2. Everything that beats winner also beats loser
  for (const item of losesTo[winnerName]) {
    if (!beatsMap[item].has(loserName)) {
      beatsMap[item].add(loserName);
      losesTo[loserName].add(item);
      scores[item]++;
      state.comparison.comparisonsSkipped++;
    }
    // And also beats everything loser beats
    for (const subItem of beatsMap[loserName]) {
      if (!beatsMap[item].has(subItem)) {
        beatsMap[item].add(subItem);
        losesTo[subItem].add(item);
        scores[item]++;
        state.comparison.comparisonsSkipped++;
      }
    }
  }
}

function exitComparisonMode() {
  state.comparison = null;
  comparisonMode.hidden = true;
  document.body.style.overflow = "";
}

function findNextUnknownPair() {
  if (!state.comparison) return null;
  const { allPairs, currentPairIndex } = state.comparison;
  
  for (let i = currentPairIndex; i < allPairs.length; i++) {
    const [left, right] = allPairs[i];
    if (!isRelationshipKnown(left, right)) {
      state.comparison.currentPairIndex = i;
      return [left, right];
    }
  }
  return null; // All pairs are known
}

function showCurrentPair() {
  if (!state.comparison) return;
  
  const nextPair = findNextUnknownPair();
  
  if (!nextPair) {
    showComparisonResults();
    return;
  }
  
  const [left, right] = nextPair;
  const { comparisonsAsked, comparisonsSkipped, allPairs } = state.comparison;
  
  // Calculate remaining unknown pairs
  let remainingUnknown = 0;
  for (let i = state.comparison.currentPairIndex; i < allPairs.length; i++) {
    const [l, r] = allPairs[i];
    if (!isRelationshipKnown(l, r)) {
      remainingUnknown++;
    }
  }
  
  const statusText = comparisonsSkipped > 0
    ? `Comparison ${comparisonsAsked + 1} (${comparisonsSkipped} inferred)`
    : `Comparison ${comparisonsAsked + 1}`;
  comparisonProgress.textContent = statusText;
  
  // Set left card
  const leftImg = compareLeft.querySelector("img");
  const leftVideo = compareLeft.querySelector("video");
  const leftName = compareLeft.querySelector(".comparison-card__name");
  
  if (left.type === "video") {
    leftImg.hidden = true;
    leftVideo.hidden = false;
    leftVideo.src = left.url;
    leftVideo.load();
  } else {
    leftVideo.hidden = true;
    leftImg.hidden = false;
    leftImg.src = left.url;
    leftImg.alt = left.name;
  }
  leftName.textContent = left.name;
  
  // Set right card
  const rightImg = compareRight.querySelector("img");
  const rightVideo = compareRight.querySelector("video");
  const rightName = compareRight.querySelector(".comparison-card__name");
  
  if (right.type === "video") {
    rightImg.hidden = true;
    rightVideo.hidden = false;
    rightVideo.src = right.url;
    rightVideo.load();
  } else {
    rightVideo.hidden = true;
    rightImg.hidden = false;
    rightImg.src = right.url;
    rightImg.alt = right.name;
  }
  rightName.textContent = right.name;
}

function selectWinner(side) {
  if (!state.comparison) return;
  
  const nextPair = findNextUnknownPair();
  if (!nextPair) {
    showComparisonResults();
    return;
  }
  
  const [left, right] = nextPair;
  
  if (side === "left") {
    recordWin(left.name, right.name);
  } else if (side === "right") {
    recordWin(right.name, left.name);
  }
  // If side is "skip", no relationship is recorded
  
  state.comparison.comparisonsAsked++;
  state.comparison.currentPairIndex++;
  showCurrentPair();
}

function showComparisonResults() {
  if (!state.comparison) return;
  
  const { scores, comparisonsAsked, comparisonsSkipped, allPairs } = state.comparison;
  
  // Sort by score descending
  const ranked = Object.entries(scores)
    .map(([name, score]) => ({ name, score }))
    .sort((a, b) => b.score - a.score);
  
  resultsList.innerHTML = "";
  
  // Show summary of comparisons
  const summaryDiv = document.createElement("div");
  summaryDiv.className = "comparison-results__summary";
  const totalPossible = allPairs.length;
  const efficiency = totalPossible > 0 
    ? Math.round((1 - comparisonsAsked / totalPossible) * 100) 
    : 0;
  summaryDiv.innerHTML = `
    <p style="text-align: center; margin-bottom: 1rem; color: var(--text-secondary);">
      ${comparisonsAsked} comparisons made, ${comparisonsSkipped} inferred automatically
      ${efficiency > 0 ? `<br><small>(${efficiency}% fewer comparisons needed)</small>` : ""}
    </p>
  `;
  resultsList.appendChild(summaryDiv);
  
  ranked.forEach((item, index) => {
    const media = state.images.find((m) => m.name === item.name);
    const div = document.createElement("div");
    div.className = "comparison-results__item";
    
    const thumb = media.type === "video" 
      ? `<video class="comparison-results__thumb" src="${media.url}" muted></video>`
      : `<img class="comparison-results__thumb" src="${media.url}" alt="" />`;
    
    div.innerHTML = `
      <span class="comparison-results__rank">#${index + 1}</span>
      ${thumb}
      <span class="comparison-results__name">${escapeHtml(item.name)}</span>
      <span class="comparison-results__score">${item.score} wins</span>
    `;
    
    resultsList.appendChild(div);
  });
  
  // Store ranked order for applying
  state.comparison.rankedOrder = ranked.map((r) => r.name);
  
  comparisonMode.hidden = true;
  comparisonResults.hidden = false;
}

async function applyRanking() {
  if (!state.comparison || !state.comparison.rankedOrder) return;
  
  const order = state.comparison.rankedOrder;
  
  // Reorder images array
  const reordered = order.map((name) => state.images.find((m) => m.name === name)).filter(Boolean);
  state.images = reordered;
  
  // Save to server
  await saveOrder();
  
  closeComparisonResults();
  renderImages();
}

function closeComparisonResults() {
  comparisonResults.hidden = true;
  document.body.style.overflow = "";
  state.comparison = null;
}

function discardRanking() {
  closeComparisonResults();
}

compareLeft.addEventListener("click", () => selectWinner("left"));
compareRight.addEventListener("click", () => selectWinner("right"));
comparisonSkipBtn.addEventListener("click", () => selectWinner("skip"));
exitComparisonBtn.addEventListener("click", exitComparisonMode);
applyRankingBtn.addEventListener("click", applyRanking);
discardRankingBtn.addEventListener("click", discardRanking);
resultsBackdrop.addEventListener("click", discardRanking);

// Global keyboard handler
document.addEventListener("keydown", (event) => {
  // Escape key handling for all modals
  if (event.key === "Escape") {
    if (!videoModal.hidden) {
      closeVideoModal();
    } else if (!deleteModal.hidden) {
      closeDeleteModal();
    } else if (!mediaViewerModal.hidden) {
      closeMediaViewer();
    } else if (!comparisonMode.hidden) {
      exitComparisonMode();
    } else if (!comparisonResults.hidden) {
      discardRanking();
    }
  }
  
  // Arrow key navigation in media viewer
  if (!mediaViewerModal.hidden) {
    if (event.key === "ArrowLeft") {
      navigateViewer(-1);
    } else if (event.key === "ArrowRight") {
      navigateViewer(1);
    }
  }
  
  // Keyboard shortcuts for comparison mode
  if (!comparisonMode.hidden) {
    if (event.key === "ArrowLeft" || event.key === "1") {
      selectWinner("left");
    } else if (event.key === "ArrowRight" || event.key === "2") {
      selectWinner("right");
    } else if (event.key === " " || event.key === "s") {
      event.preventDefault();
      selectWinner("skip");
    }
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
      if (mode === "compare") {
        startComparisonMode();
      } else {
        setViewMode(mode);
      }
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
