from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
import csv
import io

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
    Response,
)
from werkzeug.utils import secure_filename

# Pillow for thumbnails and EXIF
try:
    from PIL import Image, ExifTags
    PILLOW_AVAILABLE = True
except ImportError:
    PILLOW_AVAILABLE = False

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
THUMBS_DIR_NAME = ".thumbs"
THUMBNAIL_SIZE = (400, 400)


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
        """Load per-media metadata (tags, comments, etc.) for all files in a project."""
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

    def _get_media_comment(folder: Path, filename: str) -> str:
        """Get comment for a specific media file."""
        media_meta = _load_media_meta(folder)
        file_meta = media_meta.get(filename, {})
        return file_meta.get("comment", "")

    def _set_media_comment(folder: Path, filename: str, comment: str) -> None:
        """Set comment for a specific media file."""
        media_meta = _load_media_meta(folder)
        if filename not in media_meta:
            media_meta[filename] = {}
        media_meta[filename]["comment"] = comment
        _save_media_meta(folder, media_meta)

    def _get_file_hash(file_path: Path) -> str:
        """Calculate MD5 hash of a file for duplicate detection."""
        hash_md5 = hashlib.md5()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()

    def _get_content_hash(content: bytes) -> str:
        """Calculate MD5 hash of content bytes."""
        return hashlib.md5(content).hexdigest()

    def _load_file_hashes(folder: Path) -> Dict[str, str]:
        """Load stored file hashes for a project."""
        media_meta = _load_media_meta(folder)
        hashes = {}
        for filename, meta in media_meta.items():
            if "hash" in meta:
                hashes[meta["hash"]] = filename
        return hashes

    def _set_file_hash(folder: Path, filename: str, file_hash: str) -> None:
        """Store file hash in media metadata."""
        media_meta = _load_media_meta(folder)
        if filename not in media_meta:
            media_meta[filename] = {}
        media_meta[filename]["hash"] = file_hash
        _save_media_meta(folder, media_meta)

    def _generate_thumbnail(file_path: Path, thumbs_dir: Path) -> Optional[str]:
        """Generate a thumbnail for an image file."""
        if not PILLOW_AVAILABLE:
            return None
        
        if file_path.suffix.lower() not in IMAGE_EXTENSIONS:
            return None
        
        # Skip HEIC for now as it requires additional support
        if file_path.suffix.lower() == ".heic":
            return None
        
        thumbs_dir.mkdir(exist_ok=True)
        thumb_name = f"{file_path.stem}_thumb.webp"
        thumb_path = thumbs_dir / thumb_name
        
        try:
            with Image.open(file_path) as img:
                # Convert to RGB if necessary (for PNG with transparency, etc.)
                if img.mode in ('RGBA', 'LA', 'P'):
                    background = Image.new('RGB', img.size, (0, 0, 0))
                    if img.mode == 'P':
                        img = img.convert('RGBA')
                    background.paste(img, mask=img.split()[-1] if img.mode == 'RGBA' else None)
                    img = background
                elif img.mode != 'RGB':
                    img = img.convert('RGB')
                
                # Maintain aspect ratio
                img.thumbnail(THUMBNAIL_SIZE, Image.Resampling.LANCZOS)
                img.save(thumb_path, 'WEBP', quality=80)
            return thumb_name
        except Exception as e:
            print(f"Failed to generate thumbnail for {file_path}: {e}")
            return None

    def _extract_exif(file_path: Path) -> Dict:
        """Extract EXIF data from an image file."""
        if not PILLOW_AVAILABLE:
            return {}
        
        if file_path.suffix.lower() not in IMAGE_EXTENSIONS:
            return {}
        
        # Skip formats that don't typically have EXIF
        if file_path.suffix.lower() in {".gif", ".bmp", ".webp", ".heic"}:
            return {}
        
        try:
            with Image.open(file_path) as img:
                exif_data = img._getexif()
                if not exif_data:
                    return {}
                
                exif_dict = {}
                for tag_id, value in exif_data.items():
                    tag = ExifTags.TAGS.get(tag_id, tag_id)
                    
                    # Only include useful tags
                    if tag in ['Make', 'Model', 'DateTime', 'DateTimeOriginal', 
                               'ExposureTime', 'FNumber', 'ISOSpeedRatings', 'ISO',
                               'FocalLength', 'LensModel', 'LensMake',
                               'ExposureProgram', 'WhiteBalance', 'Flash',
                               'ImageWidth', 'ImageHeight', 'Orientation']:
                        # Convert bytes to string if needed
                        if isinstance(value, bytes):
                            try:
                                value = value.decode('utf-8', errors='ignore')
                            except:
                                continue
                        # Handle tuples (like FocalLength)
                        if isinstance(value, tuple) and len(value) == 2:
                            try:
                                value = round(value[0] / value[1], 2)
                            except:
                                pass
                        exif_dict[tag] = value
                
                return exif_dict
        except Exception as e:
            print(f"Failed to extract EXIF from {file_path}: {e}")
            return {}

    def _get_file_info(file_path: Path) -> Dict:
        """Get file information including size and dates."""
        stat = file_path.stat()
        return {
            "size": stat.st_size,
            "created": datetime.fromtimestamp(stat.st_ctime).isoformat(),
            "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
        }

    def _serialize_media(folder: Path, media_type: str = "all", sort_by: str = "rank") -> List[dict]:
        """Serialize media files with type information."""
        files = _list_media_files(folder, media_type)
        current_files = {file.name: file for file in files}
        rankings = [name for name in _load_rankings(folder) if name in current_files]
        ranked_set = set(rankings)
        remaining = [name for name in current_files if name not in rankings]
        
        # Default ordering (ranked first, then unranked by name)
        ordered = rankings + sorted(remaining)
        
        media_meta = _load_media_meta(folder)
        thumbs_dir = folder / THUMBS_DIR_NAME
        
        serialized = []
        for idx, name in enumerate(ordered, start=1):
            file_path = current_files[name]
            suffix = file_path.suffix.lower()
            is_video = suffix in VIDEO_EXTENSIONS
            file_meta = media_meta.get(name, {})
            is_ranked = name in ranked_set
            
            # Check for thumbnail
            thumb_name = f"{file_path.stem}_thumb.webp"
            has_thumb = (thumbs_dir / thumb_name).exists() if thumbs_dir.exists() else False
            
            # Get file info
            file_info = _get_file_info(file_path)
            
            item = {
                "name": name,
                "rank": idx if is_ranked else None,
                "isRanked": is_ranked,
                "url": f"/api/projects/{folder.name}/files/{name}",
                "type": "video" if is_video else "image",
                "tags": file_meta.get("tags", []),
                "comment": file_meta.get("comment", ""),
                "size": file_info["size"],
                "created": file_info["created"],
                "modified": file_info["modified"],
            }
            
            if has_thumb:
                item["thumbUrl"] = f"/api/projects/{folder.name}/thumbs/{thumb_name}"
            
            serialized.append(item)
        
        # Apply sorting
        if sort_by == "name":
            serialized.sort(key=lambda x: x["name"].lower())
        elif sort_by == "name_desc":
            serialized.sort(key=lambda x: x["name"].lower(), reverse=True)
        elif sort_by == "date":
            serialized.sort(key=lambda x: x["modified"])
        elif sort_by == "date_desc":
            serialized.sort(key=lambda x: x["modified"], reverse=True)
        elif sort_by == "size":
            serialized.sort(key=lambda x: x["size"])
        elif sort_by == "size_desc":
            serialized.sort(key=lambda x: x["size"], reverse=True)
        # Default "rank" sorting is already applied
        
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

    # ============ Health Check ============
    @app.get("/health")
    def health_check():
        """Health check endpoint for container orchestration."""
        return jsonify({
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": "1.1.0"
        })

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
        # Support sorting
        sort_by = request.args.get("sort", "rank")
        if sort_by not in ("rank", "name", "name_desc", "date", "date_desc", "size", "size_desc"):
            sort_by = "rank"
        metadata = _load_metadata(folder)
        media_items = _serialize_media(folder, media_type, sort_by)
        return jsonify(
            {
                "project": folder.name,
                "description": metadata.get("description", ""),
                "images": media_items,
                "mediaType": media_type,
                "sortBy": sort_by,
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
        
        # Check for duplicate detection flag
        check_duplicates = request.form.get("checkDuplicates", "false").lower() == "true"
        existing_hashes = _load_file_hashes(folder) if check_duplicates else {}
        
        saved = []
        duplicates = []
        thumbs_dir = folder / THUMBS_DIR_NAME
        
        for file in request.files.getlist("files"):
            if not file:
                continue
            filename = secure_filename(file.filename)
            if not filename:
                continue
            if Path(filename).suffix.lower() not in ALLOWED_EXTENSIONS:
                continue
            
            # Read file content for hash
            content = file.read()
            file.seek(0)  # Reset for saving
            
            # Check for duplicates
            if check_duplicates:
                content_hash = _get_content_hash(content)
                if content_hash in existing_hashes:
                    duplicates.append({
                        "filename": filename,
                        "existingFile": existing_hashes[content_hash]
                    })
                    continue
            
            safe_name = _next_available_name(folder, filename)
            file_path = folder / safe_name
            file.save(file_path)
            
            # Store hash for future duplicate detection
            if check_duplicates:
                content_hash = _get_content_hash(content)
                _set_file_hash(folder, safe_name, content_hash)
                existing_hashes[content_hash] = safe_name
            
            # Generate thumbnail for images
            if file_path.suffix.lower() in IMAGE_EXTENSIONS:
                _generate_thumbnail(file_path, thumbs_dir)
            
            saved.append(safe_name)
        
        response_data = {"saved": saved}
        if duplicates:
            response_data["duplicates"] = duplicates
        
        return jsonify(response_data), 201

    @app.post("/api/projects/<project_name>/check-duplicates")
    def check_duplicates(project_name: str):
        """Check if files would be duplicates before uploading."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        if "files" not in request.files:
            abort(400, description="No files provided")
        
        existing_hashes = _load_file_hashes(folder)
        duplicates = []
        new_files = []
        
        for file in request.files.getlist("files"):
            if not file:
                continue
            filename = secure_filename(file.filename)
            if not filename:
                continue
            
            content = file.read()
            content_hash = _get_content_hash(content)
            
            if content_hash in existing_hashes:
                duplicates.append({
                    "filename": filename,
                    "existingFile": existing_hashes[content_hash],
                    "hash": content_hash
                })
            else:
                new_files.append({
                    "filename": filename,
                    "hash": content_hash
                })
        
        return jsonify({
            "duplicates": duplicates,
            "newFiles": new_files
        })

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

    @app.get("/api/projects/<project_name>/thumbs/<path:filename>")
    def serve_thumbnail(project_name: str, filename: str):
        """Serve thumbnail images."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        thumbs_dir = folder / THUMBS_DIR_NAME
        file_path = (thumbs_dir / filename).resolve()
        if thumbs_dir not in file_path.parents and file_path != thumbs_dir:
            abort(400, description="Invalid file path")
        if not file_path.exists():
            abort(404, description="Thumbnail not found")
        return send_from_directory(thumbs_dir, filename)

    @app.get("/api/projects/<project_name>/files/<path:filename>/exif")
    def get_file_exif(project_name: str, filename: str):
        """Get EXIF data for an image file."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        file_path = (folder / filename).resolve()
        if folder not in file_path.parents and file_path != folder:
            abort(400, description="Invalid file path")
        if not file_path.exists():
            abort(404, description="File not found")
        
        exif_data = _extract_exif(file_path)
        file_info = _get_file_info(file_path)
        
        return jsonify({
            "filename": filename,
            "exif": exif_data,
            "fileInfo": file_info
        })

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

    @app.post("/api/projects/<project_name>/download-selected")
    def download_selected(project_name: str):
        """Download selected media files as a ZIP archive."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        
        payload = request.get_json(silent=True) or {}
        filenames = payload.get("files", [])
        
        if not filenames:
            abort(400, description="No files specified")
        
        # Create ZIP in memory
        buffer = BytesIO()
        with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
            for filename in filenames:
                file_path = (folder / filename).resolve()
                if folder in file_path.parents and file_path.exists():
                    zf.write(file_path, file_path.name)
        buffer.seek(0)
        
        return send_file(
            buffer,
            mimetype='application/zip',
            as_attachment=True,
            download_name=f"{project_name}_selected.zip"
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

    @app.put("/api/projects/<project_name>/media/<path:filename>/comment")
    def update_media_comment(project_name: str, filename: str):
        """Update comment for a specific media file."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        file_path = (folder / filename).resolve()
        if folder not in file_path.parents and file_path != folder:
            abort(400, description="Invalid file path")
        if not file_path.exists():
            abort(404, description="File not found")
        payload = request.get_json(silent=True) or {}
        comment = str(payload.get("comment", "") or "").strip()
        _set_media_comment(folder, filename, comment)
        return jsonify({"name": filename, "comment": comment})

    @app.post("/api/projects/<project_name>/batch-tags")
    def batch_update_tags(project_name: str):
        """Batch update tags for multiple media files."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        
        payload = request.get_json(silent=True) or {}
        filenames = payload.get("files", [])
        add_tags = payload.get("addTags", [])
        remove_tags = payload.get("removeTags", [])
        
        if not filenames:
            abort(400, description="No files specified")
        
        media_meta = _load_media_meta(folder)
        updated = []
        
        for filename in filenames:
            file_path = (folder / filename).resolve()
            if folder not in file_path.parents or not file_path.exists():
                continue
            
            if filename not in media_meta:
                media_meta[filename] = {}
            
            current_tags = set(media_meta[filename].get("tags", []))
            
            # Add new tags
            for tag in add_tags:
                if isinstance(tag, str) and tag.strip():
                    current_tags.add(tag.strip().lower())
            
            # Remove tags
            for tag in remove_tags:
                if isinstance(tag, str):
                    current_tags.discard(tag.strip().lower())
            
            media_meta[filename]["tags"] = list(current_tags)
            updated.append({"name": filename, "tags": list(current_tags)})
        
        _save_media_meta(folder, media_meta)
        return jsonify({"updated": updated})

    @app.delete("/api/projects/<project_name>/batch-delete")
    def batch_delete_files(project_name: str):
        """Batch delete multiple media files."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        
        payload = request.get_json(silent=True) or {}
        filenames = payload.get("files", [])
        
        if not filenames:
            abort(400, description="No files specified")
        
        deleted = []
        media_meta = _load_media_meta(folder)
        rankings = _load_rankings(folder)
        thumbs_dir = folder / THUMBS_DIR_NAME
        
        for filename in filenames:
            file_path = (folder / filename).resolve()
            if folder not in file_path.parents or not file_path.exists():
                continue
            
            # Delete the file
            file_path.unlink()
            
            # Delete thumbnail if exists
            thumb_path = thumbs_dir / f"{file_path.stem}_thumb.webp"
            if thumb_path.exists():
                thumb_path.unlink()
            
            # Remove from rankings
            if filename in rankings:
                rankings.remove(filename)
            
            # Remove from media metadata
            if filename in media_meta:
                del media_meta[filename]
            
            deleted.append(filename)
        
        _save_rankings(folder, rankings)
        _save_media_meta(folder, media_meta)
        
        return jsonify({"deleted": deleted})

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

    @app.get("/api/projects/<project_name>/export")
    def export_project_data(project_name: str):
        """Export project ranking data as JSON or CSV."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        
        format_type = request.args.get("format", "json")
        media_items = _serialize_media(folder, "all")
        metadata = _load_metadata(folder)
        
        if format_type == "csv":
            output = io.StringIO()
            writer = csv.writer(output)
            writer.writerow(["Rank", "Filename", "Type", "Tags", "Comment", "Size", "Modified"])
            
            for item in media_items:
                writer.writerow([
                    item.get("rank", ""),
                    item["name"],
                    item["type"],
                    ";".join(item.get("tags", [])),
                    item.get("comment", ""),
                    item.get("size", ""),
                    item.get("modified", "")
                ])
            
            output.seek(0)
            return Response(
                output.getvalue(),
                mimetype="text/csv",
                headers={"Content-Disposition": f"attachment; filename={project_name}_rankings.csv"}
            )
        else:
            export_data = {
                "project": project_name,
                "description": metadata.get("description", ""),
                "exportedAt": datetime.utcnow().isoformat(),
                "media": media_items
            }
            return jsonify(export_data)

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
        
        # Delete thumbnail if exists
        thumbs_dir = folder / THUMBS_DIR_NAME
        thumb_path = thumbs_dir / f"{file_path.stem}_thumb.webp"
        if thumb_path.exists():
            thumb_path.unlink()
        
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

    @app.post("/api/projects/<project_name>/generate-thumbnails")
    def generate_project_thumbnails(project_name: str):
        """Generate thumbnails for all images in a project."""
        folder = _project_path(project_name)
        if not folder.exists():
            abort(404, description="Project not found")
        
        if not PILLOW_AVAILABLE:
            abort(500, description="Pillow not available for thumbnail generation")
        
        thumbs_dir = folder / THUMBS_DIR_NAME
        media_files = _list_media_files(folder, "photos")
        
        generated = []
        for file_path in media_files:
            thumb_name = _generate_thumbnail(file_path, thumbs_dir)
            if thumb_name:
                generated.append(thumb_name)
        
        return jsonify({"generated": generated, "count": len(generated)})

    @app.get("/api/all-media")
    def get_all_media():
        """Get all media from all projects combined."""
        media_type = request.args.get("media", "all")
        if media_type not in ("all", "photos", "videos"):
            media_type = "all"
        sort_by = request.args.get("sort", "rank")
        
        all_media = []
        for folder in sorted(project_root.iterdir()):
            if not folder.is_dir():
                continue
            items = _serialize_media(folder, media_type, sort_by)
            for item in items:
                item["project"] = folder.name
                # Update URL to include project name
                item["url"] = f"/api/projects/{folder.name}/files/{item['name']}"
                if "thumbUrl" in item:
                    item["thumbUrl"] = f"/api/projects/{folder.name}/thumbs/{item['name'].rsplit('.', 1)[0]}_thumb.webp"
            all_media.extend(items)
        
        return jsonify({
            "project": "All Projects",
            "description": "Media from all projects",
            "images": all_media,
            "mediaType": media_type,
            "sortBy": sort_by,
        })

    # Serve PWA manifest
    @app.get("/manifest.json")
    def serve_manifest():
        return send_from_directory(STATIC_DIR, "manifest.json")

    # Serve service worker
    @app.get("/sw.js")
    def serve_service_worker():
        return send_from_directory(STATIC_DIR, "sw.js")

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 18473)), debug=True)
