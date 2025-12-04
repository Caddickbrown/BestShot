from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List

from flask import (
    Flask,
    abort,
    jsonify,
    render_template,
    request,
    send_from_directory,
)
from werkzeug.utils import secure_filename

BASE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = BASE_DIR.parent / "templates"
STATIC_DIR = BASE_DIR.parent / "static"
DEFAULT_PROJECT_ROOT = Path(os.environ.get("PROJECT_ROOT", "/project"))

try:
    DEFAULT_PROJECT_ROOT.mkdir(parents=True, exist_ok=True)
except PermissionError:
    fallback = BASE_DIR.parent / "project_data"
    fallback.mkdir(parents=True, exist_ok=True)
    DEFAULT_PROJECT_ROOT = fallback

ALLOWED_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".gif",
    ".bmp",
    ".tif",
    ".tiff",
    ".webp",
    ".heic",
}
RANKING_FILENAME = ".ranking.json"
META_FILENAME = ".project.json"
TAGS_FILENAME = ".tags.json"


def create_app() -> Flask:
    app = Flask(
        __name__,
        template_folder=str(TEMPLATES_DIR),
        static_folder=str(STATIC_DIR),
    )

    project_root = Path(os.environ.get("PROJECT_ROOT", str(DEFAULT_PROJECT_ROOT))).resolve()
    project_root.mkdir(parents=True, exist_ok=True)

    def _project_path(name: str) -> Path:
        safe_name = secure_filename(name)
        if not safe_name:
            abort(400, description="Invalid project name")
        project_path = (project_root / safe_name).resolve()
        if project_root not in project_path.parents and project_path != project_root:
            abort(400, description="Project path is outside of the root")
        return project_path

    def _list_projects() -> List[dict]:
        projects = []
        for folder in sorted(project_root.iterdir()):
            if not folder.is_dir():
                continue
            images = _list_image_files(folder)
            metadata = _load_metadata(folder)
            projects.append(
                {
                    "name": folder.name,
                    "imageCount": len(images),
                    "updated": datetime.fromtimestamp(folder.stat().st_mtime).isoformat(),
                    "description": metadata.get("description", ""),
                }
            )
        return projects

    def _list_image_files(folder: Path) -> List[Path]:
        files = []
        for file in folder.iterdir():
            if file.is_file() and file.suffix.lower() in ALLOWED_EXTENSIONS:
                files.append(file)
        return sorted(files)

    def _load_rankings(folder: Path) -> List[str]:
        ranking_file = folder / RANKING_FILENAME
        if ranking_file.exists():
            try:
                data = json.loads(ranking_file.read_text())
                if isinstance(data, list):
                    return [str(name) for name in data]
            except json.JSONDecodeError:
                pass
        return []

    def _save_rankings(folder: Path, order: List[str]) -> None:
        ranking_file = folder / RANKING_FILENAME
        ranking_file.write_text(json.dumps(order, indent=2))

    def _load_metadata(folder: Path) -> Dict[str, str]:
        metadata_file = folder / META_FILENAME
        if metadata_file.exists():
            try:
                data = json.loads(metadata_file.read_text())
                if isinstance(data, dict):
                    return {
                        "description": str(data.get("description", "") or ""),
                    }
            except json.JSONDecodeError:
                pass
        return {"description": ""}

    def _save_metadata(folder: Path, metadata: Dict[str, str]) -> None:
        metadata_file = folder / META_FILENAME
        metadata_file.write_text(json.dumps(metadata, indent=2))

    def _load_tags(folder: Path) -> Dict[str, List[str]]:
        tags_file = folder / TAGS_FILENAME
        if tags_file.exists():
            try:
                data = json.loads(tags_file.read_text())
                if isinstance(data, dict):
                    return {str(k): [str(t) for t in v] if isinstance(v, list) else [] for k, v in data.items()}
            except json.JSONDecodeError:
                pass
        return {}

    def _save_tags(folder: Path, tags: Dict[str, List[str]]) -> None:
        tags_file = folder / TAGS_FILENAME
        tags_file.write_text(json.dumps(tags, indent=2))

    def _serialize_images(folder: Path) -> List[dict]:
        files = _list_image_files(folder)
        current_files = {file.name: file for file in files}
        rankings = [name for name in _load_rankings(folder) if name in current_files]
        remaining = [name for name in current_files if name not in rankings]
        ordered = rankings + sorted(remaining)
        tags_data = _load_tags(folder)
        serialized = []
        for idx, name in enumerate(ordered, start=1):
            serialized.append(
                {
                    "name": name,
                    "rank": idx,
                    "url": f"/api/projects/{folder.name}/files/{name}",
                    "tags": tags_data.get(name, []),
                }
            )
        return serialized

    def _next_available_name(folder: Path, filename: str) -> str:
        candidate = filename
        stem = Path(filename).stem
        suffix = Path(filename).suffix
        counter = 1
        while (folder / candidate).exists():
            candidate = f"{stem}_{counter}{suffix}"
            counter += 1
        return candidate

    @app.route("/")
    def index() -> str:
        return render_template("index.html")

    @app.get("/api/projects")
    def get_projects():
        return jsonify({"projects": _list_projects()})

    @app.post("/api/projects")
    def create_project():
        payload = request.get_json(silent=True) or {}
        name = payload.get("name", "")
        description = str(payload.get("description", "") or "").strip()
        folder = _project_path(name)
        if folder.exists():
            abort(400, description="Project already exists")
        folder.mkdir(parents=True, exist_ok=True)
        _save_metadata(folder, {"description": description})
        return jsonify({"name": folder.name, "description": description}), 201

    @app.get("/api/projects/<project_name>/images")
    def get_project_images(project_name: str):
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        metadata = _load_metadata(folder)
        return jsonify(
            {
                "project": folder.name,
                "description": metadata.get("description", ""),
                "images": _serialize_images(folder),
            }
        )

    @app.put("/api/projects/<project_name>")
    def update_project(project_name: str):
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        payload = request.get_json(silent=True) or {}
        description = str(payload.get("description", "") or "").strip()
        _save_metadata(folder, {"description": description})
        return jsonify({"name": folder.name, "description": description})

    @app.post("/api/projects/<project_name>/upload")
    def upload_images(project_name: str):
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        if "files" not in request.files:
            abort(400, description="No files provided")
        saved = []
        for file in request.files.getlist("files"):
            if not file:
                continue
            filename = secure_filename(file.filename)
            if not filename:
                continue
            if Path(filename).suffix.lower() not in ALLOWED_EXTENSIONS:
                continue
            safe_name = _next_available_name(folder, filename)
            file.save(folder / safe_name)
            saved.append(safe_name)
        return jsonify({"saved": saved}), 201

    @app.post("/api/projects/<project_name>/rank")
    def update_rankings(project_name: str):
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        payload = request.get_json(silent=True) or {}
        order = payload.get("order")
        if not isinstance(order, list):
            abort(400, description="Order must be a list")
        current_files = {file.name for file in _list_image_files(folder)}
        cleaned_order = [name for name in order if name in current_files]
        _save_rankings(folder, cleaned_order)
        return jsonify({"order": cleaned_order})

    @app.get("/api/projects/<project_name>/files/<path:filename>")
    def serve_file(project_name: str, filename: str):
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        file_path = (folder / filename).resolve()
        if folder not in file_path.parents and file_path != folder:
            abort(400, description="Invalid file path")
        if not file_path.exists():
            abort(404, description="File not found")
        return send_from_directory(folder, filename)

    @app.put("/api/projects/<project_name>/images/<path:filename>/tags")
    def update_image_tags(project_name: str, filename: str):
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        file_path = (folder / filename).resolve()
        if folder not in file_path.parents and file_path != folder:
            abort(400, description="Invalid file path")
        if not file_path.exists():
            abort(404, description="File not found")
        payload = request.get_json(silent=True) or {}
        tags = payload.get("tags", [])
        if not isinstance(tags, list):
            abort(400, description="Tags must be a list")
        # Sanitize tags: lowercase, strip whitespace, remove empty
        clean_tags = list(dict.fromkeys(
            t.strip().lower() for t in tags if isinstance(t, str) and t.strip()
        ))
        all_tags = _load_tags(folder)
        if clean_tags:
            all_tags[filename] = clean_tags
        else:
            all_tags.pop(filename, None)
        _save_tags(folder, all_tags)
        return jsonify({"filename": filename, "tags": clean_tags})

    @app.get("/api/projects/<project_name>/tags")
    def get_project_tags(project_name: str):
        """Get all unique tags used in a project."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        all_tags = _load_tags(folder)
        unique_tags = set()
        for tags in all_tags.values():
            unique_tags.update(tags)
        return jsonify({"tags": sorted(unique_tags)})

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8000)), debug=True)
