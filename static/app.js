// ============ DOM Elements ============
const projectsList = document.getElementById("projects-list");
const newProjectForm = document.getElementById("new-project-form");
const projectNameInput = document.getElementById("project-name");
const projectDescriptionInput = document.getElementById("project-description-input");
const refreshProjectsBtn = document.getElementById("refresh-projects");
const workspaceTitle = document.getElementById("workspace-title");
const workspaceMeta = document.getElementById("workspace-meta");
const galleryDropZone = document.getElementById("gallery-drop-zone");
const dropOverlay = document.getElementById("drop-overlay");
const browseFilesBtn = document.getElementById("browse-files");
const fileInput = document.getElementById("file-input");
const deleteProjectBtn = document.getElementById("delete-project");
const allProjectsOption = document.getElementById("all-projects-option");
const imagesGrid = document.getElementById("images-grid");
const imageTemplate = document.getElementById("image-card-template");
const videoTemplate = document.getElementById("video-card-template");
const projectDescriptionForm = document.getElementById("project-description-form");
const projectDescriptionField = document.getElementById("project-description");
const projectDescriptionStatus = document.getElementById("project-description-status");
const saveDescriptionBtn = document.getElementById("save-description");
const startCompareBtn = document.getElementById("start-compare");
const mediaFilterButtons = document.querySelectorAll("[data-media-filter]");
const searchInput = document.getElementById("search-input");
const clearSearchBtn = document.getElementById("clear-search");

// Sort controls
const sortButton = document.getElementById("sort-button");
const sortLabel = document.getElementById("sort-label");
const sortDropdown = document.getElementById("sort-dropdown");
const sortOptions = sortDropdown.querySelectorAll("[data-sort]");

// Grid size controls
const gridSizeButtons = document.querySelectorAll("[data-grid-size]");

// Selection mode
const selectModeBtn = document.getElementById("select-mode-btn");
const bulkActionsBar = document.getElementById("bulk-actions-bar");
const bulkCount = document.getElementById("bulk-count");
const bulkTagBtn = document.getElementById("bulk-tag-btn");
const bulkDownloadBtn = document.getElementById("bulk-download-btn");
const bulkDeleteBtn = document.getElementById("bulk-delete-btn");
const bulkCancelBtn = document.getElementById("bulk-cancel-btn");

// Export controls
const exportBtn = document.getElementById("export-btn");
const exportDropdown = document.getElementById("export-dropdown");
const exportOptions = exportDropdown.querySelectorAll("[data-export]");

// Theme toggle
const themeToggle = document.getElementById("theme-toggle");

// Help button
const helpBtn = document.getElementById("help-btn");
const shortcutsModal = document.getElementById("shortcuts-modal");
const closeShortcutsBtn = document.getElementById("close-shortcuts");
const shortcutsBackdrop = shortcutsModal.querySelector(".shortcuts-modal__backdrop");

// Upload progress
const uploadProgress = document.getElementById("upload-progress");
const uploadProgressStatus = document.getElementById("upload-progress-status");
const uploadProgressFill = document.getElementById("upload-progress-fill");

// Duplicate modal
const duplicateModal = document.getElementById("duplicate-modal");
const duplicateList = document.getElementById("duplicate-list");
const uploadSkipDuplicatesBtn = document.getElementById("upload-skip-duplicates");
const uploadAllAnywayBtn = document.getElementById("upload-all-anyway");
const cancelUploadBtn = document.getElementById("cancel-upload");
const duplicateBackdrop = duplicateModal.querySelector(".duplicate-modal__backdrop");

// Gallery loading overlay
const galleryLoading = document.getElementById("gallery-loading");

// Comparison selection modal elements
const comparisonSelection = document.getElementById("comparison-selection");
const compareAllBtn = document.getElementById("compare-all");
const compareUnrankedBtn = document.getElementById("compare-unranked");
const compareAllCount = document.getElementById("compare-all-count");
const compareUnrankedCount = document.getElementById("compare-unranked-count");
const cancelComparisonSelectionBtn = document.getElementById("cancel-comparison-selection");
const comparisonSelectionBackdrop = comparisonSelection.querySelector(".comparison-selection__backdrop");

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

// Project select modal elements (for file drops in All Projects view)
const projectSelectModal = document.getElementById("project-select-modal");
const projectSelectList = document.getElementById("project-select-list");
const projectSelectNewName = document.getElementById("project-select-new-name");
const projectSelectCreateBtn = document.getElementById("project-select-create");
const projectSelectCancelBtn = document.getElementById("project-select-cancel");
const projectSelectBackdrop = projectSelectModal.querySelector(".project-select-modal__backdrop");

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
const viewerDownloadBtn = document.getElementById("viewer-download-btn");
const viewerCommentInput = document.getElementById("viewer-comment-input");
const viewerExifPanel = document.getElementById("viewer-exif");
const exifGrid = document.getElementById("exif-grid");
const downloadAllBtn = document.getElementById("download-all");

// Slideshow controls
const slideshowControls = document.getElementById("slideshow-controls");
const slideshowToggle = document.getElementById("slideshow-toggle");
const slideshowTimer = document.getElementById("slideshow-timer");

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

// ============ Application State ============
const state = {
  projects: [],
  currentProject: null,
  isAllProjects: false,
  images: [],
  description: "",
  mediaFilter: "all",
  searchQuery: "",
  sortBy: "rank",
  gridSize: "medium",
  viewerIndex: -1,
  comparison: null,
  comparisonScope: "all",
  pendingFiles: null,
  isSelectionMode: false,
  selectedItems: new Set(),
  isSlideshow: false,
  slideshowInterval: null,
  slideshowDelay: 3000,
  theme: localStorage.getItem("theme") || "dark",
  pendingUploadFiles: null, // For duplicate detection flow
};

// Touch drag-and-drop state
let touchDragState = null;

// ============ Theme Management ============
function initTheme() {
  if (state.theme === "light") {
    document.body.classList.add("light-theme");
    themeToggle.textContent = "☀️";
  } else {
    document.body.classList.remove("light-theme");
    themeToggle.textContent = "🌙";
  }
}

function toggleTheme() {
  state.theme = state.theme === "dark" ? "light" : "dark";
  localStorage.setItem("theme", state.theme);
  initTheme();
}

themeToggle.addEventListener("click", toggleTheme);
initTheme();

// ============ URL State Persistence ============
function getStateFromURL() {
  const params = new URLSearchParams(window.location.search);
  return {
    project: params.get("project"),
    media: params.get("media"),
    sort: params.get("sort"),
  };
}

function updateURL() {
  const params = new URLSearchParams();
  if (state.isAllProjects) {
    params.set("project", "all");
  } else if (state.currentProject) {
    params.set("project", state.currentProject);
  }
  if (state.mediaFilter && state.mediaFilter !== "all") {
    params.set("media", state.mediaFilter);
  }
  if (state.sortBy && state.sortBy !== "rank") {
    params.set("sort", state.sortBy);
  }
  const newURL = params.toString()
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;
  window.history.replaceState({}, "", newURL);
}

function restoreStateFromURL() {
  const urlState = getStateFromURL();
  if (urlState.media === "photos" || urlState.media === "videos" || urlState.media === "all") {
    state.mediaFilter = urlState.media;
    mediaFilterButtons.forEach((button) => {
      button.classList.toggle("active", button.dataset.mediaFilter === state.mediaFilter);
    });
  }
  if (urlState.sort) {
    state.sortBy = urlState.sort;
    updateSortUI();
  }
  return urlState.project;
}

// ============ Sort Controls ============
function updateSortUI() {
  const labels = {
    rank: "Rank",
    name: "Name (A-Z)",
    name_desc: "Name (Z-A)",
    date: "Date (Oldest)",
    date_desc: "Date (Newest)",
    size: "Size (Smallest)",
    size_desc: "Size (Largest)",
  };
  sortLabel.textContent = labels[state.sortBy] || "Rank";
  sortOptions.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.sort === state.sortBy);
  });
}

sortButton.addEventListener("click", (e) => {
  e.stopPropagation();
  sortDropdown.hidden = !sortDropdown.hidden;
});

sortOptions.forEach((btn) => {
  btn.addEventListener("click", async () => {
    state.sortBy = btn.dataset.sort;
    updateSortUI();
    sortDropdown.hidden = true;
    updateURL();
    await loadProjectState();
  });
});

document.addEventListener("click", () => {
  sortDropdown.hidden = true;
  exportDropdown.hidden = true;
});

// ============ Grid Size Controls ============
function updateGridSize() {
  imagesGrid.classList.remove("grid-small", "grid-medium", "grid-large");
  imagesGrid.classList.add(`grid-${state.gridSize}`);
  gridSizeButtons.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.gridSize === state.gridSize);
  });
}

gridSizeButtons.forEach((btn) => {
  btn.addEventListener("click", () => {
    state.gridSize = btn.dataset.gridSize;
    localStorage.setItem("gridSize", state.gridSize);
    updateGridSize();
  });
});

// Restore grid size from localStorage
const savedGridSize = localStorage.getItem("gridSize");
if (savedGridSize) {
  state.gridSize = savedGridSize;
}

// ============ Export Controls ============
exportBtn.addEventListener("click", (e) => {
  e.stopPropagation();
  exportDropdown.hidden = !exportDropdown.hidden;
});

exportOptions.forEach((btn) => {
  btn.addEventListener("click", () => {
    const format = btn.dataset.export;
    exportDropdown.hidden = true;
    if (state.currentProject) {
      const url = `/api/projects/${encodeURIComponent(state.currentProject)}/export?format=${format}`;
      window.open(url, "_blank");
    }
  });
});

// ============ Keyboard Shortcuts Modal ============
function openShortcutsModal() {
  shortcutsModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeShortcutsModal() {
  shortcutsModal.hidden = true;
  document.body.style.overflow = "";
}

helpBtn.addEventListener("click", openShortcutsModal);
closeShortcutsBtn.addEventListener("click", closeShortcutsModal);
shortcutsBackdrop.addEventListener("click", closeShortcutsModal);

// ============ Fetch Projects ============
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
    state.isAllProjects = false;
    state.images = [];
    disableWorkspace();
    updateURL();
    return;
  }

  if (initialProjectFromURL === "all") {
    if (!state.isAllProjects) {
      await selectAllProjects();
    }
    return;
  }

  let targetProject = null;
  if (initialProjectFromURL && state.projects.some((p) => p.name === initialProjectFromURL)) {
    targetProject = initialProjectFromURL;
  } else if (state.currentProject && state.projects.some((p) => p.name === state.currentProject)) {
    targetProject = state.currentProject;
  } else if (state.isAllProjects) {
    return;
  } else {
    targetProject = state.projects[0].name;
  }

  if (targetProject !== state.currentProject) {
    await selectProject(targetProject);
  }
}

function renderProjects() {
  projectsList.innerHTML = "";
  
  allProjectsOption.classList.toggle("active", state.isAllProjects);
  
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

    if (!state.isAllProjects && state.currentProject === project.name) {
      li.classList.add("active");
    }

    li.addEventListener("click", () => selectProject(project.name));
    projectsList.appendChild(li);
  });
}

async function selectProject(name) {
  state.currentProject = name;
  state.isAllProjects = false;
  exitSelectionMode();
  renderProjects();
  updateURL();
  await loadProjectState();
}

async function selectAllProjects() {
  state.currentProject = null;
  state.isAllProjects = true;
  exitSelectionMode();
  renderProjects();
  updateURL();
  await loadAllProjectsState();
}

async function loadAllProjectsState() {
  showGalleryLoading(true);
  const url = `/api/all-media?media=${state.mediaFilter}&sort=${state.sortBy}`;
  const res = await fetch(url);
  showGalleryLoading(false);
  if (!res.ok) {
    alert("Unable to load media");
    return;
  }
  const data = await res.json();
  state.images = data.images;
  state.description = "";
  workspaceTitle.textContent = "All Projects";
  
  const imageCount = state.images.filter((m) => m.type === "image").length;
  const videoCount = state.images.filter((m) => m.type === "video").length;
  const parts = [];
  if (imageCount > 0) parts.push(`${imageCount} photo${imageCount === 1 ? "" : "s"}`);
  if (videoCount > 0) parts.push(`${videoCount} video${videoCount === 1 ? "" : "s"}`);
  workspaceMeta.textContent = parts.length ? parts.join(", ") : "No media";
  
  projectDescriptionField.value = "";
  projectDescriptionStatus.textContent = "All projects view";
  enableWorkspace();
  renderImages();
}

async function loadProjectState() {
  if (state.isAllProjects) {
    await loadAllProjectsState();
    return;
  }
  if (!state.currentProject) {
    disableWorkspace();
    return;
  }
  showGalleryLoading(true);
  const url = `/api/projects/${encodeURIComponent(state.currentProject)}/images?media=${state.mediaFilter}&sort=${state.sortBy}`;
  const res = await fetch(url);
  showGalleryLoading(false);
  if (!res.ok) {
    alert("Unable to load project");
    return;
  }
  const data = await res.json();
  state.images = data.images;
  state.description = data.description || "";
  workspaceTitle.textContent = data.project;
  
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

function showGalleryLoading(show) {
  galleryLoading.hidden = !show;
}

function getFilteredImages() {
  if (!state.searchQuery.trim()) {
    return state.images;
  }
  const query = state.searchQuery.toLowerCase().trim();
  return state.images.filter((media) => {
    if (media.name.toLowerCase().includes(query)) {
      return true;
    }
    if (media.tags && media.tags.some((tag) => tag.toLowerCase().includes(query))) {
      return true;
    }
    return false;
  });
}

function renderImages() {
  imagesGrid.innerHTML = "";
  imagesGrid.classList.add("gallery");
  updateGridSize();

  const filteredImages = getFilteredImages();

  if (!state.images.length) {
    const empty = document.createElement("div");
    empty.className = "empty-gallery";
    let emptyText = "Select a project to begin.";
    if (state.currentProject) {
      if (state.mediaFilter === "photos") {
        emptyText = "No photos yet.";
      } else if (state.mediaFilter === "videos") {
        emptyText = "No videos yet.";
      } else {
        emptyText = "No media yet.";
      }
      empty.innerHTML = `
        <p class="muted">${emptyText}</p>
        <p class="muted">Drag files here or use the Browse button</p>
      `;
    } else {
      empty.innerHTML = `<p class="muted">${emptyText}</p>`;
    }
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
    card.dataset.isRanked = media.isRanked;
    card.classList.add("is-gallery");
    
    // Selection mode
    if (state.isSelectionMode) {
      card.classList.add("selectable");
      if (state.selectedItems.has(media.name)) {
        card.classList.add("selected");
      }
      // Add checkbox
      const checkbox = document.createElement("div");
      checkbox.className = "selection-checkbox";
      checkbox.textContent = "✓";
      card.style.position = "relative";
      card.appendChild(checkbox);
    }
    
    const rank = card.querySelector(".rank-pill");
    if (media.isRanked) {
      rank.textContent = `#${media.rank}`;
      rank.classList.remove("unranked");
    } else {
      rank.textContent = "New";
      rank.classList.add("unranked");
    }
    card.querySelector(".filename").textContent = media.name;

    // Show project badge in All Projects view
    if (state.isAllProjects && media.project) {
      const projectBadge = document.createElement("span");
      projectBadge.className = "project-badge";
      projectBadge.textContent = media.project;
      projectBadge.title = `Project: ${media.project}`;
      card.querySelector(".image-card__head").insertBefore(
        projectBadge,
        card.querySelector(".filename")
      );
    }

    if (isVideo) {
      const video = card.querySelector("video");
      video.src = `${media.url}?v=${Date.now()}`;
      video.addEventListener("loadeddata", () => {
        video.currentTime = 0.1;
      });
      
      const playButton = card.querySelector(".play-button");
      playButton.addEventListener("click", (event) => {
        event.stopPropagation();
        if (!state.isSelectionMode) {
          openMediaViewer(index);
        }
      });
    } else {
      const img = card.querySelector("img");
      // Use thumbnail if available
      const imgUrl = media.thumbUrl || media.url;
      img.src = `${imgUrl}?v=${Date.now()}`;
      img.alt = media.name;
    }

    // Click handler
    card.style.cursor = "pointer";
    card.addEventListener("click", (event) => {
      if (event.target.closest(".image-card__tags")) return;
      if (event.target.closest(".drag-handle")) return;
      if (event.target.closest(".delete-media-btn")) return;
      if (event.target.closest(".download-media-btn")) return;
      
      if (state.isSelectionMode) {
        toggleItemSelection(media.name);
        card.classList.toggle("selected", state.selectedItems.has(media.name));
        updateBulkActionsBar();
      } else {
        openMediaViewer(index);
      }
    });

    // Download button handler
    const downloadBtn = card.querySelector(".download-media-btn");
    downloadBtn.addEventListener("click", (event) => {
      event.stopPropagation();
      const projectName = media.project || state.currentProject;
      if (projectName) {
        downloadMediaFile(projectName, media.name);
      }
    });

    // Delete button handler
    const deleteBtn = card.querySelector(".delete-media-btn");
    deleteBtn.addEventListener("click", (event) => {
      event.stopPropagation();
      const projectName = media.project || state.currentProject;
      if (projectName) {
        deleteMediaFile(projectName, media.name);
      }
    });

    // Render tags
    renderCardTags(card, media);

    // Drag-drop for reordering (only when not in selection mode and not searching)
    const canDrag = !state.searchQuery && !state.isAllProjects && !state.isSelectionMode;
    card.draggable = canDrag;
    if (canDrag) {
      card.addEventListener("dragstart", (event) => {
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("application/x-gallery-card", originalIndex.toString());
        card.classList.add("dragging");
        card.dataset.dragIndex = originalIndex;
      });

      card.addEventListener("dragend", () => {
        card.classList.remove("dragging");
      });

      card.addEventListener("dragover", (event) => {
        const isCardDrag = event.dataTransfer.types.includes("application/x-gallery-card");
        if (isCardDrag) {
          event.preventDefault();
          const dragged = document.querySelector(".image-card.dragging");
          if (dragged && dragged !== card) {
            card.classList.add("over");
          }
        }
      });

      card.addEventListener("dragleave", () => card.classList.remove("over"));

      card.addEventListener("drop", (event) => {
        card.classList.remove("over");
        
        const isCardDrag = event.dataTransfer.types.includes("application/x-gallery-card");
        if (!isCardDrag) {
          event.preventDefault();
          return;
        }
        
        event.preventDefault();
        const dragged = document.querySelector(".image-card.dragging");
        if (!dragged) return;
        const from = Number(dragged.dataset.dragIndex);
        const to = Number(card.dataset.index);
        reorderImages(from, to);
      });

      // Touch drag-and-drop
      card.addEventListener("touchstart", handleTouchStart, { passive: false });
      card.addEventListener("touchmove", handleTouchMove, { passive: false });
      card.addEventListener("touchend", handleTouchEnd, { passive: false });
    }

    imagesGrid.appendChild(card);
  });

  updateActionStates();
}

// ============ Selection Mode ============
function enterSelectionMode() {
  state.isSelectionMode = true;
  state.selectedItems.clear();
  selectModeBtn.textContent = "Cancel";
  selectModeBtn.classList.add("active");
  renderImages();
  updateBulkActionsBar();
}

function exitSelectionMode() {
  state.isSelectionMode = false;
  state.selectedItems.clear();
  selectModeBtn.textContent = "Select";
  selectModeBtn.classList.remove("active");
  bulkActionsBar.hidden = true;
  renderImages();
}

function toggleItemSelection(name) {
  if (state.selectedItems.has(name)) {
    state.selectedItems.delete(name);
  } else {
    state.selectedItems.add(name);
  }
}

function updateBulkActionsBar() {
  const count = state.selectedItems.size;
  bulkActionsBar.hidden = count === 0;
  bulkCount.textContent = `${count} selected`;
}

selectModeBtn.addEventListener("click", () => {
  if (state.isSelectionMode) {
    exitSelectionMode();
  } else {
    enterSelectionMode();
  }
});

bulkCancelBtn.addEventListener("click", exitSelectionMode);

bulkDeleteBtn.addEventListener("click", async () => {
  if (state.selectedItems.size === 0) return;
  if (!confirm(`Delete ${state.selectedItems.size} selected file(s)? This cannot be undone.`)) return;
  
  const projectName = state.currentProject;
  if (!projectName) return;
  
  const res = await fetch(`/api/projects/${encodeURIComponent(projectName)}/batch-delete`, {
    method: "DELETE",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ files: Array.from(state.selectedItems) }),
  });
  
  if (!res.ok) {
    alert("Failed to delete files");
    return;
  }
  
  exitSelectionMode();
  await loadProjectState();
  await fetchProjects();
});

bulkDownloadBtn.addEventListener("click", async () => {
  if (state.selectedItems.size === 0) return;
  
  const projectName = state.currentProject;
  if (!projectName) return;
  
  // Create a form to POST and download
  const form = document.createElement("form");
  form.method = "POST";
  form.action = `/api/projects/${encodeURIComponent(projectName)}/download-selected`;
  form.style.display = "none";
  
  const input = document.createElement("input");
  input.type = "hidden";
  input.name = "files";
  input.value = JSON.stringify(Array.from(state.selectedItems));
  form.appendChild(input);
  
  document.body.appendChild(form);
  
  // Use fetch to trigger download
  const res = await fetch(`/api/projects/${encodeURIComponent(projectName)}/download-selected`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ files: Array.from(state.selectedItems) }),
  });
  
  if (res.ok) {
    const blob = await res.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${projectName}_selected.zip`;
    a.click();
    window.URL.revokeObjectURL(url);
  } else {
    alert("Failed to download files");
  }
  
  document.body.removeChild(form);
});

bulkTagBtn.addEventListener("click", async () => {
  if (state.selectedItems.size === 0) return;
  
  const tag = prompt("Enter tag to add to selected items:");
  if (!tag || !tag.trim()) return;
  
  const projectName = state.currentProject;
  if (!projectName) return;
  
  const res = await fetch(`/api/projects/${encodeURIComponent(projectName)}/batch-tags`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      files: Array.from(state.selectedItems),
      addTags: [tag.trim()],
    }),
  });
  
  if (!res.ok) {
    alert("Failed to add tag");
    return;
  }
  
  await loadProjectState();
});

// ============ Tag Functions ============
function renderCardTags(card, media) {
  const tagsContainer = card.querySelector(".tags-list");
  const addTagBtn = card.querySelector(".add-tag-btn");
  const tagInputWrapper = card.querySelector(".tag-input-wrapper");
  const tagInput = card.querySelector(".tag-input");
  const tagsSection = card.querySelector(".image-card__tags");
  
  tagsSection.hidden = false;

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

  addTagBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    tagInputWrapper.hidden = false;
    addTagBtn.hidden = true;
    tagInput.focus();
  });

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
  const media = state.images.find((m) => m.name === filename);
  if (!media) return;
  
  const projectName = media.project || state.currentProject;
  if (!projectName) return;

  const currentTags = media.tags || [];
  const normalizedTag = tag.trim().toLowerCase();
  if (currentTags.includes(normalizedTag)) return;

  const newTags = [...currentTags, normalizedTag];
  await updateMediaTags(projectName, filename, newTags);
}

async function removeTag(filename, tag) {
  const media = state.images.find((m) => m.name === filename);
  if (!media) return;
  
  const projectName = media.project || state.currentProject;
  if (!projectName) return;

  const currentTags = media.tags || [];
  const newTags = currentTags.filter((t) => t !== tag);
  await updateMediaTags(projectName, filename, newTags);
}

function downloadMediaFile(projectName, filename) {
  if (!projectName) return;
  
  const downloadUrl = `/api/projects/${encodeURIComponent(projectName)}/files/${encodeURIComponent(filename)}/download`;
  const link = document.createElement("a");
  link.href = downloadUrl;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

async function downloadProject(projectName) {
  if (!projectName) return;
  
  const downloadUrl = `/api/projects/${encodeURIComponent(projectName)}/download`;
  const link = document.createElement("a");
  link.href = downloadUrl;
  link.download = `${projectName}.zip`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

async function deleteMediaFile(projectName, filename) {
  if (!projectName) return;
  
  if (!confirm(`Delete "${filename}"? This cannot be undone.`)) {
    return;
  }
  
  const res = await fetch(
    `/api/projects/${encodeURIComponent(projectName)}/files/${encodeURIComponent(filename)}`,
    { method: "DELETE" }
  );
  
  if (!res.ok) {
    alert("Failed to delete file");
    return;
  }
  
  if (state.isAllProjects) {
    await loadAllProjectsState();
    await fetchProjects();
  } else {
    await loadProjectState();
    await fetchProjects();
  }
}

async function updateMediaTags(projectName, filename, tags) {
  if (!projectName) return;

  const res = await fetch(
    `/api/projects/${encodeURIComponent(projectName)}/media/${encodeURIComponent(filename)}/tags`,
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
  const media = state.images.find((m) => m.name === filename);
  if (media) {
    media.tags = data.tags;
  }
  renderImages();
}

async function reorderImages(from, to) {
  if (Number.isNaN(from) || Number.isNaN(to) || from === to) {
    return;
  }
  if (from < 0 || from >= state.images.length || to < 0 || to >= state.images.length) {
    return;
  }
  if (state.isAllProjects) {
    return;
  }
  const [moved] = state.images.splice(from, 1);
  state.images.splice(to, 0, moved);
  renderImages();
  await saveOrder();
}

// ============ Touch Drag-and-Drop Support ============
function handleTouchStart(event) {
  const card = event.currentTarget;
  const touch = event.touches[0];

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

  if (!touchDragState.isDragging) {
    if (deltaX > touchDragState.scrollThreshold || deltaY > touchDragState.scrollThreshold) {
      touchDragState.isDragging = true;
      touchDragState.card.classList.add("dragging");

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
    event.preventDefault();

    touchDragState.currentX = touch.clientX;
    touchDragState.currentY = touch.clientY;

    if (touchDragState.clone) {
      touchDragState.clone.style.left = `${touch.clientX - touchDragState.offsetX}px`;
      touchDragState.clone.style.top = `${touch.clientY - touchDragState.offsetY}px`;
    }

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

  if (clone) {
    clone.remove();
  }

  card.classList.remove("dragging");

  if (isDragging) {
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

// ============ Workspace State ============
function disableWorkspace() {
  galleryDropZone.classList.add("disabled");
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
  galleryDropZone.classList.remove("disabled");
  projectDescriptionField.disabled = false;
  saveDescriptionBtn.disabled = false;
  updateActionStates();
}

function updateActionStates() {
  const hasProject = Boolean(state.currentProject);
  const hasSelection = hasProject || state.isAllProjects;
  const hasMedia = state.images.length > 0;
  browseFilesBtn.disabled = !hasProject;
  saveDescriptionBtn.disabled = !hasProject;
  projectDescriptionField.disabled = !hasProject;
  deleteProjectBtn.disabled = !hasProject;
  downloadAllBtn.disabled = !hasProject || !hasMedia;
  startCompareBtn.disabled = !hasSelection || state.images.length < 2;
  selectModeBtn.disabled = !hasProject || !hasMedia;
  exportBtn.disabled = !hasProject;
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

// ============ Upload with Progress & Duplicate Detection ============
async function uploadFiles(files, skipDuplicateCheck = false) {
  if (!state.currentProject || !files.length) return;

  const filesArray = Array.isArray(files) ? files : Array.from(files);
  if (!filesArray.length) return;

  // Check for duplicates first if not skipping
  if (!skipDuplicateCheck) {
    const checkFormData = new FormData();
    filesArray.forEach((file) => {
      if (file instanceof File) {
        checkFormData.append("files", file);
      }
    });

    try {
      const checkRes = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}/check-duplicates`, {
        method: "POST",
        body: checkFormData,
      });

      if (checkRes.ok) {
        const checkData = await checkRes.json();
        if (checkData.duplicates && checkData.duplicates.length > 0) {
          // Store files and show modal
          state.pendingUploadFiles = filesArray;
          showDuplicateModal(checkData.duplicates);
          return;
        }
      }
    } catch (e) {
      // Continue with upload if check fails
      console.error("Duplicate check failed:", e);
    }
  }

  // Proceed with upload
  await performUpload(filesArray);
}

async function performUpload(filesArray) {
  const formData = new FormData();
  filesArray.forEach((file) => {
    if (file instanceof File) {
      formData.append("files", file);
    }
  });

  // Show progress
  uploadProgress.hidden = false;
  uploadProgressFill.style.width = "0%";
  uploadProgressStatus.textContent = "0%";

  try {
    // Use XMLHttpRequest for progress tracking
    await new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      
      xhr.upload.addEventListener("progress", (e) => {
        if (e.lengthComputable) {
          const percent = Math.round((e.loaded / e.total) * 100);
          uploadProgressFill.style.width = `${percent}%`;
          uploadProgressStatus.textContent = `${percent}%`;
        }
      });

      xhr.addEventListener("load", () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve(xhr.response);
        } else {
          reject(new Error(xhr.statusText));
        }
      });

      xhr.addEventListener("error", () => reject(new Error("Upload failed")));

      xhr.open("POST", `/api/projects/${encodeURIComponent(state.currentProject)}/upload`);
      xhr.send(formData);
    });

    uploadProgressFill.style.width = "100%";
    uploadProgressStatus.textContent = "Complete!";
    
    setTimeout(() => {
      uploadProgress.hidden = true;
    }, 1500);

    await loadProjectState();
    await fetchProjects();
  } catch (error) {
    console.error("Upload error:", error);
    uploadProgress.hidden = true;
    alert(`Upload failed: ${error.message || "Network error. Please try again."}`);
  }
}

function showDuplicateModal(duplicates) {
  duplicateList.innerHTML = "";
  duplicates.forEach((dup) => {
    const item = document.createElement("div");
    item.className = "duplicate-list__item";
    item.innerHTML = `
      <span class="duplicate-list__new">${escapeHtml(dup.filename)}</span>
      <span class="duplicate-list__existing">matches ${escapeHtml(dup.existingFile)}</span>
    `;
    duplicateList.appendChild(item);
  });
  duplicateModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeDuplicateModal() {
  duplicateModal.hidden = true;
  document.body.style.overflow = "";
  state.pendingUploadFiles = null;
}

uploadSkipDuplicatesBtn.addEventListener("click", async () => {
  if (!state.pendingUploadFiles) return;
  closeDuplicateModal();
  // Upload with duplicate check enabled (server will skip duplicates)
  const formData = new FormData();
  state.pendingUploadFiles.forEach((file) => {
    if (file instanceof File) {
      formData.append("files", file);
    }
  });
  formData.append("checkDuplicates", "true");
  
  uploadProgress.hidden = false;
  uploadProgressFill.style.width = "0%";
  
  try {
    const res = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}/upload`, {
      method: "POST",
      body: formData,
    });
    
    uploadProgressFill.style.width = "100%";
    uploadProgressStatus.textContent = "Complete!";
    
    setTimeout(() => {
      uploadProgress.hidden = true;
    }, 1500);

    if (!res.ok) {
      throw new Error("Upload failed");
    }
    
    await loadProjectState();
    await fetchProjects();
  } catch (error) {
    uploadProgress.hidden = true;
    alert("Upload failed: " + error.message);
  }
});

uploadAllAnywayBtn.addEventListener("click", async () => {
  if (!state.pendingUploadFiles) return;
  const files = state.pendingUploadFiles;
  closeDuplicateModal();
  await performUpload(files);
});

cancelUploadBtn.addEventListener("click", closeDuplicateModal);
duplicateBackdrop.addEventListener("click", closeDuplicateModal);

async function saveOrder() {
  if (!state.currentProject || state.isAllProjects) return;
  const order = state.images.map((img) => img.name);
  const res = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}/rank`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ order }),
  });

  if (!res.ok) {
    console.error("Failed to save ranking");
    return;
  }
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

// ============ Project Selection Modal Functions ============
function openProjectSelectModal(files) {
  state.pendingFiles = files;
  
  projectSelectList.innerHTML = "";
  state.projects.forEach((project) => {
    const btn = document.createElement("button");
    btn.className = "project-select-modal__item";
    btn.innerHTML = `
      <span class="project-select-modal__item-name">${escapeHtml(project.name)}</span>
      <span class="project-select-modal__item-count">${project.mediaCount} files</span>
    `;
    btn.addEventListener("click", () => selectProjectForUpload(project.name));
    projectSelectList.appendChild(btn);
  });
  
  projectSelectNewName.value = "";
  projectSelectModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeProjectSelectModal() {
  projectSelectModal.hidden = true;
  document.body.style.overflow = "";
  state.pendingFiles = null;
}

async function selectProjectForUpload(projectName) {
  if (!state.pendingFiles) return;
  
  const files = state.pendingFiles;
  closeProjectSelectModal();
  
  const filesArray = Array.isArray(files) ? files : Array.from(files);
  if (!filesArray.length) return;
  
  const formData = new FormData();
  filesArray.forEach((file) => {
    if (file instanceof File) {
      formData.append("files", file);
    }
  });
  
  try {
    const res = await fetch(`/api/projects/${encodeURIComponent(projectName)}/upload`, {
      method: "POST",
      body: formData,
    });
    
    if (!res.ok) {
      const errorText = await res.text().catch(() => "Unknown error");
      alert(`Upload failed: ${errorText || "Make sure the files are supported images/videos."}`);
      return;
    }
    
    await loadAllProjectsState();
    await fetchProjects();
  } catch (error) {
    console.error("Upload error:", error);
    alert(`Upload failed: ${error.message || "Network error. Please try again."}`);
  }
}

async function createProjectAndUpload() {
  const name = projectSelectNewName.value.trim();
  if (!name) {
    alert("Please enter a project name");
    return;
  }
  
  if (!state.pendingFiles) return;
  
  const createRes = await fetch("/api/projects", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, description: "" }),
  });
  
  if (!createRes.ok) {
    const error = await createRes.text();
    alert(error || "Failed to create project");
    return;
  }
  
  const created = await createRes.json();
  await selectProjectForUpload(created.name);
}

projectSelectCreateBtn.addEventListener("click", createProjectAndUpload);
projectSelectCancelBtn.addEventListener("click", closeProjectSelectModal);
projectSelectBackdrop.addEventListener("click", closeProjectSelectModal);

projectSelectNewName.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    createProjectAndUpload();
  } else if (e.key === "Escape") {
    closeProjectSelectModal();
  }
});

// ============ Media Viewer Functions ============
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
    slideshowControls.hidden = true;
  } else {
    viewerVideo.hidden = true;
    viewerImage.hidden = false;
    viewerImage.src = media.url; // Use full image, not thumbnail
    viewerImage.alt = media.name;
    slideshowControls.hidden = false;
  }
  
  renderViewerTags(media);
  loadViewerComment(media);
  loadViewerExif(media);
  
  mediaViewerModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeMediaViewer() {
  stopSlideshow();
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

function loadViewerComment(media) {
  viewerCommentInput.value = media.comment || "";
}

async function saveViewerComment() {
  const filteredImages = getFilteredImages();
  const media = filteredImages[state.viewerIndex];
  if (!media) return;
  
  const projectName = media.project || state.currentProject;
  if (!projectName) return;
  
  const comment = viewerCommentInput.value.trim();
  
  const res = await fetch(
    `/api/projects/${encodeURIComponent(projectName)}/media/${encodeURIComponent(media.name)}/comment`,
    {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ comment }),
    }
  );
  
  if (res.ok) {
    media.comment = comment;
  }
}

viewerCommentInput.addEventListener("blur", saveViewerComment);
viewerCommentInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    saveViewerComment();
  }
});

async function loadViewerExif(media) {
  viewerExifPanel.hidden = true;
  exifGrid.innerHTML = "";
  
  if (media.type !== "image") return;
  
  const projectName = media.project || state.currentProject;
  if (!projectName) return;
  
  try {
    const res = await fetch(
      `/api/projects/${encodeURIComponent(projectName)}/files/${encodeURIComponent(media.name)}/exif`
    );
    
    if (!res.ok) return;
    
    const data = await res.json();
    const exif = data.exif || {};
    const fileInfo = data.fileInfo || {};
    
    // Show file size
    if (fileInfo.size) {
      addExifItem("Size", formatFileSize(fileInfo.size));
    }
    
    // Show EXIF data
    if (exif.Make) addExifItem("Camera", exif.Make);
    if (exif.Model) addExifItem("Model", exif.Model);
    if (exif.DateTimeOriginal) addExifItem("Date", exif.DateTimeOriginal);
    if (exif.FNumber) addExifItem("Aperture", `f/${exif.FNumber}`);
    if (exif.ExposureTime) {
      const exposure = exif.ExposureTime < 1 
        ? `1/${Math.round(1/exif.ExposureTime)}s` 
        : `${exif.ExposureTime}s`;
      addExifItem("Shutter", exposure);
    }
    if (exif.ISOSpeedRatings || exif.ISO) addExifItem("ISO", exif.ISOSpeedRatings || exif.ISO);
    if (exif.FocalLength) addExifItem("Focal", `${exif.FocalLength}mm`);
    if (exif.LensModel) addExifItem("Lens", exif.LensModel);
    
    if (exifGrid.children.length > 0) {
      viewerExifPanel.hidden = false;
    }
  } catch (e) {
    console.error("Failed to load EXIF:", e);
  }
}

function addExifItem(label, value) {
  const item = document.createElement("div");
  item.className = "exif-panel__item";
  item.innerHTML = `
    <span class="exif-panel__label">${escapeHtml(label)}</span>
    <span class="exif-panel__value">${escapeHtml(String(value))}</span>
  `;
  exifGrid.appendChild(item);
}

function formatFileSize(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

async function addViewerTag(filename, tag) {
  const media = state.images.find((m) => m.name === filename);
  if (!media) return;
  
  const projectName = media.project || state.currentProject;
  if (!projectName) return;
  
  const currentTags = media.tags || [];
  const normalizedTag = tag.trim().toLowerCase();
  if (currentTags.includes(normalizedTag)) return;
  
  const newTags = [...currentTags, normalizedTag];
  await updateMediaTags(projectName, filename, newTags);
  
  const updatedMedia = state.images.find((m) => m.name === filename);
  if (updatedMedia) renderViewerTags(updatedMedia);
}

async function removeViewerTag(filename, tag) {
  const media = state.images.find((m) => m.name === filename);
  if (!media) return;
  
  const projectName = media.project || state.currentProject;
  if (!projectName) return;
  
  const currentTags = media.tags || [];
  const newTags = currentTags.filter((t) => t !== tag);
  await updateMediaTags(projectName, filename, newTags);
  
  const updatedMedia = state.images.find((m) => m.name === filename);
  if (updatedMedia) renderViewerTags(updatedMedia);
}

// ============ Slideshow Functions ============
function startSlideshow() {
  state.isSlideshow = true;
  slideshowToggle.textContent = "⏸ Pause";
  let countdown = state.slideshowDelay / 1000;
  slideshowTimer.textContent = countdown;
  
  state.slideshowInterval = setInterval(() => {
    countdown--;
    slideshowTimer.textContent = countdown;
    
    if (countdown <= 0) {
      navigateViewer(1);
      countdown = state.slideshowDelay / 1000;
    }
  }, 1000);
}

function stopSlideshow() {
  state.isSlideshow = false;
  slideshowToggle.textContent = "▶ Slideshow";
  slideshowTimer.textContent = "";
  
  if (state.slideshowInterval) {
    clearInterval(state.slideshowInterval);
    state.slideshowInterval = null;
  }
}

function toggleSlideshow() {
  if (state.isSlideshow) {
    stopSlideshow();
  } else {
    startSlideshow();
  }
}

slideshowToggle.addEventListener("click", toggleSlideshow);

viewerCloseBtn.addEventListener("click", closeMediaViewer);
viewerBackdrop.addEventListener("click", closeMediaViewer);
viewerPrevBtn.addEventListener("click", () => navigateViewer(-1));
viewerNextBtn.addEventListener("click", () => navigateViewer(1));

viewerDownloadBtn.addEventListener("click", () => {
  const filteredImages = getFilteredImages();
  const media = filteredImages[state.viewerIndex];
  if (media) {
    const projectName = media.project || state.currentProject;
    if (projectName) {
      downloadMediaFile(projectName, media.name);
    }
  }
});

downloadAllBtn.addEventListener("click", () => {
  if (state.currentProject) {
    downloadProject(state.currentProject);
  }
});

const viewerContent = mediaViewerModal.querySelector(".media-viewer-modal__content");
viewerContent.addEventListener("click", (event) => {
  if (event.target === viewerContent) {
    closeMediaViewer();
  }
});

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
  const pairs = [];
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      pairs.push([items[i], items[j]]);
    }
  }
  for (let i = pairs.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pairs[i], pairs[j]] = [pairs[j], pairs[i]];
  }
  return pairs;
}

function getUnrankedItems() {
  return state.images.filter((img) => !img.isRanked);
}

function openComparisonSelection() {
  const allCount = state.images.length;
  const unrankedCount = getUnrankedItems().length;
  
  compareAllCount.textContent = `${allCount} item${allCount === 1 ? "" : "s"}`;
  compareUnrankedCount.textContent = `${unrankedCount} new item${unrankedCount === 1 ? "" : "s"}`;
  
  const canCompareUnranked = unrankedCount >= 1 && allCount >= 2;
  compareUnrankedBtn.disabled = !canCompareUnranked;
  if (!canCompareUnranked) {
    compareUnrankedBtn.classList.add("disabled-option");
  } else {
    compareUnrankedBtn.classList.remove("disabled-option");
  }
  
  comparisonSelection.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeComparisonSelection() {
  comparisonSelection.hidden = true;
  document.body.style.overflow = "";
}

function startComparisonMode(scope = "all") {
  state.comparisonScope = scope;
  
  const itemsToCompare = [...state.images];
  const unrankedItems = getUnrankedItems();
  const unrankedNames = new Set(unrankedItems.map((img) => img.name));
  
  if (scope === "unranked" && unrankedItems.length < 1) {
    alert("Need at least 1 unranked item to compare");
    return;
  }
  
  if (itemsToCompare.length < 2) {
    alert("Need at least 2 items to start comparison mode");
    return;
  }
  
  closeComparisonSelection();
  
  const scores = {};
  const beatsMap = {};
  const losesTo = {};
  
  itemsToCompare.forEach((img) => {
    scores[img.name] = 0;
    beatsMap[img.name] = new Set();
    losesTo[img.name] = new Set();
  });
  
  if (scope === "unranked") {
    const rankedItems = state.images.filter((img) => img.isRanked);
    rankedItems.sort((a, b) => a.rank - b.rank);
    
    for (let i = 0; i < rankedItems.length; i++) {
      for (let j = i + 1; j < rankedItems.length; j++) {
        const winner = rankedItems[i].name;
        const loser = rankedItems[j].name;
        beatsMap[winner].add(loser);
        losesTo[loser].add(winner);
        scores[winner]++;
      }
    }
  }
  
  let allPairs;
  if (scope === "unranked") {
    allPairs = generatePairsWithUnranked(itemsToCompare, unrankedNames);
  } else {
    allPairs = generatePairs(itemsToCompare);
  }
  
  state.comparison = {
    allPairs,
    currentPairIndex: 0,
    scores,
    beatsMap,
    losesTo,
    comparisonsAsked: 0,
    comparisonsSkipped: 0,
    itemsToCompare,
    unrankedNames,
  };
  
  comparisonMode.hidden = false;
  document.body.style.overflow = "hidden";
  
  showCurrentPair();
}

function generatePairsWithUnranked(items, unrankedNames) {
  const pairs = [];
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      if (unrankedNames.has(items[i].name) || unrankedNames.has(items[j].name)) {
        pairs.push([items[i], items[j]]);
      }
    }
  }
  for (let i = pairs.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pairs[i], pairs[j]] = [pairs[j], pairs[i]];
  }
  return pairs;
}

function isRelationshipKnown(itemA, itemB) {
  if (!state.comparison) return false;
  const { beatsMap } = state.comparison;
  return beatsMap[itemA.name].has(itemB.name) || beatsMap[itemB.name].has(itemA.name);
}

function recordWin(winnerName, loserName) {
  if (!state.comparison) return;
  const { beatsMap, losesTo, scores } = state.comparison;
  
  if (beatsMap[winnerName].has(loserName)) return;
  
  beatsMap[winnerName].add(loserName);
  losesTo[loserName].add(winnerName);
  scores[winnerName]++;
  
  for (const item of beatsMap[loserName]) {
    if (!beatsMap[winnerName].has(item)) {
      beatsMap[winnerName].add(item);
      losesTo[item].add(winnerName);
      scores[winnerName]++;
      state.comparison.comparisonsSkipped++;
    }
  }
  
  for (const item of losesTo[winnerName]) {
    if (!beatsMap[item].has(loserName)) {
      beatsMap[item].add(loserName);
      losesTo[loserName].add(item);
      scores[item]++;
      state.comparison.comparisonsSkipped++;
    }
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
  return null;
}

function showCurrentPair() {
  if (!state.comparison) return;
  
  const nextPair = findNextUnknownPair();
  
  if (!nextPair) {
    showComparisonResults();
    return;
  }
  
  const [left, right] = nextPair;
  const { comparisonsAsked, comparisonsSkipped } = state.comparison;
  
  const statusText = comparisonsSkipped > 0
    ? `Comparison ${comparisonsAsked + 1} (${comparisonsSkipped} inferred)`
    : `Comparison ${comparisonsAsked + 1}`;
  comparisonProgress.textContent = statusText;
  
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
  
  state.comparison.comparisonsAsked++;
  state.comparison.currentPairIndex++;
  showCurrentPair();
}

function showComparisonResults() {
  if (!state.comparison) return;
  
  const { scores, comparisonsAsked, comparisonsSkipped, allPairs } = state.comparison;
  
  const ranked = Object.entries(scores)
    .map(([name, score]) => ({ name, score }))
    .sort((a, b) => b.score - a.score);
  
  resultsList.innerHTML = "";
  
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
      : `<img class="comparison-results__thumb" src="${media.thumbUrl || media.url}" alt="" />`;
    
    div.innerHTML = `
      <span class="comparison-results__rank">#${index + 1}</span>
      ${thumb}
      <span class="comparison-results__name">${escapeHtml(item.name)}</span>
      <span class="comparison-results__score">${item.score} wins</span>
    `;
    
    resultsList.appendChild(div);
  });
  
  state.comparison.rankedOrder = ranked.map((r) => r.name);
  
  comparisonMode.hidden = true;
  comparisonResults.hidden = false;
}

async function applyRanking() {
  if (!state.comparison || !state.comparison.rankedOrder) return;
  
  const rankedOrder = state.comparison.rankedOrder;
  
  const reordered = rankedOrder.map((name) => state.images.find((m) => m.name === name)).filter(Boolean);
  reordered.forEach((m, idx) => {
    m.isRanked = true;
    m.rank = idx + 1;
  });
  state.images = reordered;
  
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

// ============ Global Keyboard Handler ============
document.addEventListener("keydown", (event) => {
  // ? key for shortcuts
  if (event.key === "?" && !event.target.matches("input, textarea")) {
    openShortcutsModal();
    return;
  }
  
  if (event.key === "Escape") {
    if (!shortcutsModal.hidden) {
      closeShortcutsModal();
    } else if (!videoModal.hidden) {
      closeVideoModal();
    } else if (!deleteModal.hidden) {
      closeDeleteModal();
    } else if (!projectSelectModal.hidden) {
      closeProjectSelectModal();
    } else if (!duplicateModal.hidden) {
      closeDuplicateModal();
    } else if (!mediaViewerModal.hidden) {
      closeMediaViewer();
    } else if (!comparisonSelection.hidden) {
      closeComparisonSelection();
    } else if (!comparisonMode.hidden) {
      exitComparisonMode();
    } else if (!comparisonResults.hidden) {
      discardRanking();
    } else if (state.isSelectionMode) {
      exitSelectionMode();
    }
  }
  
  // P for slideshow toggle
  if (event.key === "p" || event.key === "P") {
    if (!mediaViewerModal.hidden && !event.target.matches("input, textarea")) {
      toggleSlideshow();
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

// ============ Form Event Handlers ============
newProjectForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const name = projectNameInput.value.trim();
  if (!name) return;
  await createProject(name, projectDescriptionInput.value.trim());
});

projectDescriptionForm.addEventListener("submit", saveDescription);

refreshProjectsBtn.addEventListener("click", fetchProjects);

startCompareBtn.addEventListener("click", openComparisonSelection);
compareAllBtn.addEventListener("click", () => startComparisonMode("all"));
compareUnrankedBtn.addEventListener("click", () => startComparisonMode("unranked"));
cancelComparisonSelectionBtn.addEventListener("click", closeComparisonSelection);
comparisonSelectionBackdrop.addEventListener("click", closeComparisonSelection);

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

allProjectsOption.addEventListener("click", selectAllProjects);

// Drop overlay text elements
const dropOverlayText = document.getElementById("drop-overlay-text");
const dropOverlaySubtext = document.getElementById("drop-overlay-subtext");

// Gallery drop zone for file uploads
galleryDropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  if (galleryDropZone.classList.contains("disabled")) return;
  const isCardDrag = event.dataTransfer.types.includes("application/x-gallery-card");
  if (!isCardDrag && event.dataTransfer.types.includes("Files")) {
    if (state.isAllProjects) {
      dropOverlayText.textContent = "Drop files to add";
      dropOverlaySubtext.textContent = "You'll choose which project to add them to";
    } else {
      dropOverlayText.textContent = "Drop files to add to gallery";
      dropOverlaySubtext.textContent = 'New items will be marked as "Unranked"';
    }
    dropOverlay.hidden = false;
  }
});

galleryDropZone.addEventListener("dragleave", (event) => {
  if (!galleryDropZone.contains(event.relatedTarget)) {
    dropOverlay.hidden = true;
  }
});

galleryDropZone.addEventListener("drop", (event) => {
  event.preventDefault();
  dropOverlay.hidden = true;
  
  const isCardDrag = event.dataTransfer.types.includes("application/x-gallery-card");
  if (isCardDrag) return;
  
  if (event.dataTransfer.files.length > 0) {
    const files = Array.from(event.dataTransfer.files);
    if (state.isAllProjects) {
      openProjectSelectModal(files);
    } else if (state.currentProject) {
      uploadFiles(files);
    }
  }
});

// ============ Initialize App ============
const initialProject = restoreStateFromURL();
disableWorkspace();
updateActionStates();
updateSortUI();
fetchProjects(initialProject);

// Handle browser back/forward navigation
window.addEventListener("popstate", () => {
  const urlState = getStateFromURL();
  if (urlState.project === "all" && !state.isAllProjects) {
    selectAllProjects();
  } else if (urlState.project && urlState.project !== "all" && urlState.project !== state.currentProject) {
    selectProject(urlState.project);
  }
  if (urlState.media && urlState.media !== state.mediaFilter) {
    setMediaFilter(urlState.media);
  }
});
