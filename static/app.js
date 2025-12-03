const projectsList = document.getElementById("projects-list");
const newProjectForm = document.getElementById("new-project-form");
const projectNameInput = document.getElementById("project-name");
const refreshProjectsBtn = document.getElementById("refresh-projects");
const workspaceTitle = document.getElementById("workspace-title");
const workspaceMeta = document.getElementById("workspace-meta");
const dropZone = document.getElementById("drop-zone");
const browseFilesBtn = document.getElementById("browse-files");
const fileInput = document.getElementById("file-input");
const saveOrderBtn = document.getElementById("save-order");
const imagesGrid = document.getElementById("images-grid");
const imageTemplate = document.getElementById("image-card-template");

const state = {
  projects: [],
  currentProject: null,
  images: [],
};

async function fetchProjects() {
  const res = await fetch("/api/projects");
  if (!res.ok) {
    console.error("Failed to load projects");
    return;
  }
  const data = await res.json();
  state.projects = data.projects;
  if (!state.projects.length) {
    state.currentProject = null;
    renderProjects();
    disableWorkspace();
    return;
  }
  renderProjects();
  const exists = state.projects.some((project) => project.name === state.currentProject);
  if (!exists) {
    await selectProject(state.projects[0].name);
  }
}

function renderProjects() {
  projectsList.innerHTML = "";
  if (!state.projects.length) {
    const empty = document.createElement("li");
    empty.textContent = "No projects yet";
    empty.style.justifyContent = "center";
    empty.style.opacity = "0.7";
    projectsList.appendChild(empty);
    return;
  }

  state.projects.forEach((project) => {
    const li = document.createElement("li");
    const name = document.createElement("span");
    name.textContent = project.name;
    const count = document.createElement("small");
    count.textContent = `${project.imageCount}`;
    li.append(name, count);
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
  await loadImages();
}

async function loadImages() {
  if (!state.currentProject) {
    disableWorkspace();
    return;
  }
  const res = await fetch(`/api/projects/${encodeURIComponent(state.currentProject)}/images`);
  if (!res.ok) {
    alert("Unable to load project images");
    return;
  }
  const data = await res.json();
  state.images = data.images;
  workspaceTitle.textContent = state.currentProject;
  workspaceMeta.textContent = `${state.images.length} image${state.images.length === 1 ? "" : "s"}`;
  enableWorkspace();
  renderImages();
}

function renderImages() {
  imagesGrid.innerHTML = "";
  if (!state.images.length) {
    const empty = document.createElement("p");
    empty.textContent = "No images yet. Drop them above!";
    empty.style.opacity = "0.6";
    imagesGrid.appendChild(empty);
    return;
  }

  state.images.forEach((image, index) => {
    const card = imageTemplate.content.firstElementChild.cloneNode(true);
    card.dataset.index = index;
    card.querySelector(".rank-pill").textContent = `#${index + 1}`;
    const img = card.querySelector("img");
    img.src = `${image.url}?v=${Date.now()}`;
    img.alt = image.name;
    card.querySelector(".filename").textContent = image.name;

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
      const from = Number(document.querySelector(".image-card.dragging")?.dataset.dragIndex);
      const to = Number(card.dataset.index);
      reorderImages(from, to);
    });

    imagesGrid.appendChild(card);
  });
}

function reorderImages(from, to) {
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
  browseFilesBtn.disabled = true;
  saveOrderBtn.disabled = true;
}

function enableWorkspace() {
  dropZone.classList.remove("disabled");
  dropZone.innerHTML = "<p>Drag & drop photos here or browse to upload.</p><small>Only image formats (JPG, PNG, TIFF, WebP, HEIC) are accepted.</small>";
  browseFilesBtn.disabled = false;
  saveOrderBtn.disabled = false;
}

async function createProject(name) {
  const res = await fetch("/api/projects", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name }),
  });
  if (!res.ok) {
    const error = await res.text();
    alert(error || "Failed to create project");
    return;
  }
  const created = await res.json();
  projectNameInput.value = "";
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

  await loadImages();
}

async function saveOrder() {
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
    saveOrderBtn.textContent = "Save ranking";
  }, 1500);
}

newProjectForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const value = projectNameInput.value.trim();
  if (!value) return;
  await createProject(value);
});

refreshProjectsBtn.addEventListener("click", fetchProjects);
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
  const files = event.dataTransfer.files;
  uploadFiles(files);
});

fetchProjects();
disableWorkspace();
