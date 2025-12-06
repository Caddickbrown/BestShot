from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List

import shutil

from io import BytesIO
import zipfile

from flask import (
    Flask,
    abort,
    jsonify,
    render_template,
    request,
    send_file,
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

IMAGE_EXTENSIONS = {
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

VIDEO_EXTENSIONS = {
    ".mp4",
    ".mov",
    ".avi",
    ".mkv",
    ".webm",
    ".m4v",
    ".wmv",
    ".flv",
    ".3gp",
}

ALLOWED_EXTENSIONS = IMAGE_EXTENSIONS | VIDEO_EXTENSIONS
RANKING_FILENAME = ".ranking.json"
META_FILENAME = ".project.json"
MEDIA_META_FILENAME = ".media-meta.json"


def create_app() -> Flask:
    app = Flask(
        __name__,
        template_folder=str(TEMPLATES_DIR),
        static_folder=str(STATIC_DIR),
    )

    # Add CORS headers to all responses
    @app.after_request
    def after_request(response):
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
        response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
        return response

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
            all_media = _list_media_files(folder, "all")
            images = [f for f in all_media if f.suffix.lower() in IMAGE_EXTENSIONS]
            videos = [f for f in all_media if f.suffix.lower() in VIDEO_EXTENSIONS]
            metadata = _load_metadata(folder)
            projects.append(
                {
                    "name": folder.name,
                    "imageCount": len(images),
                    "videoCount": len(videos),
                    "mediaCount": len(all_media),
                    "updated": datetime.fromtimestamp(folder.stat().st_mtime).isoformat(),
                    "description": metadata.get("description", ""),
                }
            )
        return projects

    def _list_media_files(folder: Path, media_type: str = "all") -> List[Path]:
        """List media files filtered by type: 'all', 'photos', or 'videos'."""
        if media_type == "photos":
            extensions = IMAGE_EXTENSIONS
        elif media_type == "videos":
            extensions = VIDEO_EXTENSIONS
        else:
            extensions = ALLOWED_EXTENSIONS

        files = []
        for file in folder.iterdir():
            if file.is_file() and file.suffix.lower() in extensions:
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

    def _load_media_meta(folder: Path) -> Dict[str, Dict]:
        """Load per-media metadata (tags, etc.) for all files in a project."""
        meta_file = folder / MEDIA_META_FILENAME
        if meta_file.exists():
            try:
                data = json.loads(meta_file.read_text())
                if isinstance(data, dict):
                    return data
            except json.JSONDecodeError:
                pass
        return {}

    def _save_media_meta(folder: Path, media_meta: Dict[str, Dict]) -> None:
        """Save per-media metadata for all files in a project."""
        meta_file = folder / MEDIA_META_FILENAME
        meta_file.write_text(json.dumps(media_meta, indent=2))

    def _get_media_tags(folder: Path, filename: str) -> List[str]:
        """Get tags for a specific media file."""
        media_meta = _load_media_meta(folder)
        file_meta = media_meta.get(filename, {})
        return file_meta.get("tags", [])

    def _set_media_tags(folder: Path, filename: str, tags: List[str]) -> None:
        """Set tags for a specific media file."""
        media_meta = _load_media_meta(folder)
        if filename not in media_meta:
            media_meta[filename] = {}
        media_meta[filename]["tags"] = tags
        _save_media_meta(folder, media_meta)

    def _serialize_media(folder: Path, media_type: str = "all") -> List[dict]:
        """Serialize media files with type information."""
        files = _list_media_files(folder, media_type)
        current_files = {file.name: file for file in files}
        rankings = [name for name in _load_rankings(folder) if name in current_files]
        ranked_set = set(rankings)
        remaining = [name for name in current_files if name not in rankings]
        ordered = rankings + sorted(remaining)
        media_meta = _load_media_meta(folder)
        serialized = []
        for idx, name in enumerate(ordered, start=1):
            file_path = current_files[name]
            suffix = file_path.suffix.lower()
            is_video = suffix in VIDEO_EXTENSIONS
            file_meta = media_meta.get(name, {})
            is_ranked = name in ranked_set
            serialized.append(
                {
                    "name": name,
                    "rank": idx if is_ranked else None,
                    "isRanked": is_ranked,
                    "url": f"/api/projects/{folder.name}/files/{name}",
                    "type": "video" if is_video else "image",
                    "tags": file_meta.get("tags", []),
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
        # Support filtering by media type: 'all', 'photos', or 'videos'
        media_type = request.args.get("media", "all")
        if media_type not in ("all", "photos", "videos"):
            media_type = "all"
        metadata = _load_metadata(folder)
        media_items = _serialize_media(folder, media_type)
        return jsonify(
            {
                "project": folder.name,
                "description": metadata.get("description", ""),
                "images": media_items,
                "mediaType": media_type,
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
        current_files = {file.name for file in _list_media_files(folder, "all")}
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

    @app.get("/api/projects/<project_name>/files/<path:filename>/download")
    def download_file(project_name: str, filename: str):
        """Download a single media file."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        file_path = (folder / filename).resolve()
        if folder not in file_path.parents and file_path != folder:
            abort(400, description="Invalid file path")
        if not file_path.exists():
            abort(404, description="File not found")
        return send_from_directory(folder, filename, as_attachment=True)

    @app.get("/api/projects/<project_name>/download")
    def download_project(project_name: str):
        """Download all media files in a project as a ZIP archive."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        
        media_files = _list_media_files(folder, "all")
        if not media_files:
            abort(400, description="No media files to download")
        
        # Create ZIP in memory
        buffer = BytesIO()
        with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
            for file_path in media_files:
                zf.write(file_path, file_path.name)
        buffer.seek(0)
        
        return send_file(
            buffer,
            mimetype='application/zip',
            as_attachment=True,
            download_name=f"{project_name}.zip"
        )

    @app.put("/api/projects/<project_name>/media/<path:filename>/tags")
    def update_media_tags(project_name: str, filename: str):
        """Update tags for a specific media file."""
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
        # Normalize tags: strip whitespace, lowercase, remove duplicates
        clean_tags = list(dict.fromkeys(
            tag.strip().lower() for tag in tags if isinstance(tag, str) and tag.strip()
        ))
        _set_media_tags(folder, filename, clean_tags)
        return jsonify({"name": filename, "tags": clean_tags})

    @app.get("/api/projects/<project_name>/tags")
    def get_project_tags(project_name: str):
        """Get all unique tags used in a project."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        media_meta = _load_media_meta(folder)
        all_tags = set()
        for file_meta in media_meta.values():
            all_tags.update(file_meta.get("tags", []))
        return jsonify({"tags": sorted(all_tags)})

    @app.delete("/api/projects/<project_name>")
    def delete_project(project_name: str):
        """Delete a project and all its contents."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        shutil.rmtree(folder)
        return jsonify({"deleted": project_name}), 200

    @app.delete("/api/projects/<project_name>/files/<path:filename>")
    def delete_media_file(project_name: str, filename: str):
        """Delete a specific media file from a project."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        file_path = (folder / filename).resolve()
        if folder not in file_path.parents and file_path != folder:
            abort(400, description="Invalid file path")
        if not file_path.exists():
            abort(404, description="File not found")
        
        # Delete the file
        file_path.unlink()
        
        # Remove from rankings if present
        rankings = _load_rankings(folder)
        if filename in rankings:
            rankings.remove(filename)
            _save_rankings(folder, rankings)
        
        # Remove from media metadata if present
        media_meta = _load_media_meta(folder)
        if filename in media_meta:
            del media_meta[filename]
            _save_media_meta(folder, media_meta)
        
        return jsonify({"deleted": filename}), 200

    @app.get("/api/all-media")
    def get_all_media():
        """Get all media from all projects combined."""
        media_type = request.args.get("media", "all")
        if media_type not in ("all", "photos", "videos"):
            media_type = "all"
        
        all_media = []
        for folder in sorted(project_root.iterdir()):
            if not folder.is_dir():
                continue
            items = _serialize_media(folder, media_type)
            for item in items:
                item["project"] = folder.name
                # Update URL to include project name
                item["url"] = f"/api/projects/{folder.name}/files/{item['name']}"
            all_media.extend(items)
        
        return jsonify({
            "project": "All Projects",
            "description": "Media from all projects",
            "images": all_media,
            "mediaType": media_type,
        })

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 18473)), debug=True)
