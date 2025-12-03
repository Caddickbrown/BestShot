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
const projectDescriptionForm = document.getElementById("project-description-form");
const projectDescriptionField = document.getElementById("project-description");
const projectDescriptionStatus = document.getElementById("project-description-status");
const saveDescriptionBtn = document.getElementById("save-description");
const viewModeButtons = document.querySelectorAll("[data-view-mode]");

const state = {
  projects: [],
  currentProject: null,
  images: [],
  description: "",
  viewMode: "rank",
};

async function fetchProjects() {
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
    return;
  }

  const exists = state.projects.some((project) => project.name === state.currentProject);
  if (!state.currentProject || !exists) {
    await selectProject(state.projects[0].name);
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
    details.textContent = `${project.imageCount} file${project.imageCount === 1 ? "" : "s"}`;
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
  await loadProjectState();
}

async function loadProjectState() {
  if (!state.currentProject) {
    disableWorkspace();
    return;
  }
  const res = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}/images`);
  if (!res.ok) {
    alert("Unable to load project");
    return;
  }
  const data = await res.json();
  state.images = data.images;
  state.description = data.description || "";
  workspaceTitle.textContent = data.project;
  workspaceMeta.textContent = `${state.images.length} image${state.images.length === 1 ? "" : "s"}`;
  projectDescriptionField.value = state.description;
  projectDescriptionStatus.textContent = state.description ? "Saved" : "No note";
  enableWorkspace();
  renderImages();
}

function renderImages() {
  imagesGrid.innerHTML = "";
  imagesGrid.classList.toggle("gallery", state.viewMode === "gallery");

  if (!state.images.length) {
    const empty = document.createElement("p");
    empty.textContent = state.currentProject
      ? "No images yet. Drop them into the project folder."
      : "Select a project to begin.";
    empty.classList.add("muted");
    imagesGrid.appendChild(empty);
    updateActionStates();
    return;
  }

  state.images.forEach((image, index) => {
    const card = imageTemplate.content.firstElementChild.cloneNode(true);
    card.dataset.index = index;
    card.classList.toggle("is-gallery", state.viewMode === "gallery");
    const rank = card.querySelector(".rank-pill");
    rank.textContent = `#${index + 1}`;
    const img = card.querySelector("img");
    img.src = `${image.url}?v=${Date.now()}`;
    img.alt = image.name;
    card.querySelector(".filename").textContent = image.name;

    card.draggable = state.viewMode === "rank";
    if (state.viewMode === "rank") {
      card.addEventListener("dragstart", (event) => {
        event.dataTransfer.effectAllowed = "move";
        card.classList.add("dragging");
        card.dataset.dragIndex = index;
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
    }

    imagesGrid.appendChild(card);
  });

  updateActionStates();
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
  renderImages();
}

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

fetchProjects();
disableWorkspace();
updateActionStates();
