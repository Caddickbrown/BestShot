# BestShot

A web-based media ranking tool that helps you compare and sort photos and videos by preference. Built with Flask and vanilla JavaScript, BestShot runs in any modern web browser and works seamlessly across devices.

## Features

### Core Features
- **Photo and video support** — Rank both photos and videos in the same project
- **Media type filtering** — View all media, photos only, or videos only
- **Fullscreen media viewer** — Click any photo or video to view it fullscreen with arrow key navigation
- **Drag-and-drop ranking** — Reorder media by dragging them (auto-saves on drop)
- **Comparison mode** — Side-by-side comparison to rank media by preference with smart transitive inference
- **All Projects view** — View and browse all media from all projects in one place
- **Cross-device sync** — Start ranking on your laptop, continue on your phone by sharing the URL
- **Project management** — Organize media into separate projects with descriptions
- **Tagging system** — Add tags to individual photos and videos
- **Search** — Search media by filename or tags
- **Media deletion** — Delete individual photos/videos or entire projects
- **URL state persistence** — Bookmark or share a URL to return to the same project and filter
- **Responsive design** — Optimized for screens from mobile phones to large monitors
- **Touch-friendly** — Full touch support for ranking on phones and tablets

### New Features

#### Performance & UX
- **Image thumbnails** — Auto-generated WebP thumbnails for faster gallery loading
- **Upload progress indicator** — Real-time progress bar during file uploads
- **Loading states** — Visual feedback with spinners during async operations
- **Grid size options** — Choose between small, medium, and large thumbnail sizes

#### Bulk Operations
- **Selection mode** — Multi-select media for batch operations
- **Bulk tagging** — Add tags to multiple files at once
- **Bulk download** — Download selected files as a ZIP archive
- **Bulk delete** — Delete multiple files at once

#### Media Information
- **EXIF metadata display** — View camera info (make, model, aperture, shutter speed, ISO, focal length) in the fullscreen viewer
- **Comments/notes** — Add personal notes to individual photos and videos
- **File size display** — See file sizes in the viewer

#### Sorting & Organization
- **Multiple sort options** — Sort by rank, name (A-Z, Z-A), date (newest/oldest), or size (largest/smallest)
- **Duplicate detection** — Warns when uploading files that already exist in the project

#### Viewing
- **Slideshow mode** — Auto-advance through images in fullscreen viewer (press P or click Slideshow button)
- **Keyboard shortcuts help** — Press ? to see all available keyboard shortcuts

#### Export & Sharing
- **Export rankings** — Export project data as JSON or CSV
- **Download all** — Download entire project as a ZIP file

#### Customization
- **Light/Dark theme** — Toggle between light and dark modes (preference saved)
- **PWA support** — Install as a Progressive Web App for offline viewing

## Browser Compatibility

BestShot works on all modern browsers:

- **Desktop**: Chrome, Firefox, Safari, Edge (latest versions)
- **Mobile**: iOS Safari, Android Chrome, Samsung Internet

The app uses standard web technologies (HTML5, CSS3, ES6 JavaScript) without any framework dependencies.

## Supported Media Formats

### Images
- JPEG / JPG
- PNG
- GIF
- BMP
- TIFF
- WebP
- HEIC

### Videos
- MP4
- MOV (QuickTime)
- AVI
- MKV
- WebM
- M4V
- WMV
- FLV
- 3GP

## Quick Start

### Prerequisites

- Python 3.8+
- Flask
- Pillow (optional, for thumbnail generation and EXIF extraction)
- Gunicorn (optional, for production deployment)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Caddickbrown/BestShot.git
   cd BestShot
   ```

2. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Run the application:
   ```bash
   python app/main.py
   ```

4. Open your browser to `http://localhost:18473`

### Using Docker

Build and run BestShot in a container:

```bash
docker build -t bestshot .
docker run -p 18473:18473 -v /path/to/your/images:/project bestshot
```

Or use Docker Compose:

```bash
docker-compose up -d
```

Mount your images directory to `/project` inside the container.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `←` `→` | Navigate images in viewer |
| `Esc` | Close modal / Exit mode |
| `P` | Toggle slideshow |
| `?` | Show keyboard shortcuts help |
| `1` or `←` | Pick left (in comparison mode) |
| `2` or `→` | Pick right (in comparison mode) |
| `Space` or `S` | Skip/Tie (in comparison mode) |

## Usage

### Creating a Project

1. Enter a project name in the "Create project" field
2. Optionally add a description
3. Click "Spin up"

### Adding Media

- **Drag & drop** files into the gallery area
- **Click "Browse"** to select files from your device

New uploads are marked as "New" (unranked) until you rank them.

### Ranking Media

There are two ways to rank your media:

#### Drag-and-Drop

1. **On desktop**: Drag cards to reorder them
2. **On mobile/tablet**: Touch and drag cards to reorder
3. Rankings are **automatically saved** when you drop a card

#### Comparison Mode

For a more guided ranking experience, use comparison mode:

1. Click the **"Compare"** button in the header
2. Choose to compare **All Items** or just **New Items** (unranked)
3. Click on the preferred image in each side-by-side comparison
4. Use **Skip** if two items are tied
5. When complete, click **"Apply Ranking"** to save the new order

Comparison mode uses transitive inference to reduce the number of comparisons needed — if A beats B and B beats C, it knows A beats C without asking.

### Bulk Operations

1. Click **"Select"** to enter selection mode
2. Click on photos/videos to select them (checkmarks appear)
3. Use the bulk action bar at the bottom:
   - **Add Tag** — Add a tag to all selected items
   - **Download** — Download selected items as a ZIP
   - **Delete** — Delete all selected items
4. Click **"Cancel"** to exit selection mode

### Sorting Media

Click the sort dropdown to change the order:
- **Rank** — Your custom ranking (default)
- **Name (A-Z / Z-A)** — Alphabetical order
- **Date (Newest / Oldest)** — By file modification date
- **Size (Largest / Smallest)** — By file size

### Grid Size

Use the S/M/L buttons to adjust thumbnail size:
- **S** — Small thumbnails (more items visible)
- **M** — Medium thumbnails (default)
- **L** — Large thumbnails (better detail)

### Viewing Media

- Click on any photo or video to open the fullscreen media viewer
- Use **← →** arrow keys or click the navigation arrows to browse
- View EXIF camera data (if available)
- Add or edit notes/comments
- Add or remove tags directly in the viewer
- Start a slideshow with the **▶ Slideshow** button or press **P**
- Press **Escape** or click outside to close

### Exporting Data

Click the **"Export"** button and choose:
- **Export JSON** — Full project data including rankings, tags, and metadata
- **Export CSV** — Spreadsheet-friendly format with rank, filename, tags, etc.

### Switching Devices

BestShot stores your current project and media filter in the URL. To continue on another device:

1. Copy the URL from your browser's address bar
2. Open that URL on your other device
3. Your project and filter settings will be automatically restored

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `18473` | Server port |
| `PROJECT_ROOT` | `/project` | Directory where project folders are stored |

### Example

```bash
PORT=3000 PROJECT_ROOT=/home/user/photos python app/main.py
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check endpoint |
| GET | `/api/projects` | List all projects |
| POST | `/api/projects` | Create a new project |
| GET | `/api/projects/<name>/images` | Get media for a project (supports `media` and `sort` query params) |
| PUT | `/api/projects/<name>` | Update project description |
| DELETE | `/api/projects/<name>` | Delete a project and all its contents |
| POST | `/api/projects/<name>/upload` | Upload photos and videos |
| POST | `/api/projects/<name>/check-duplicates` | Check for duplicate files before upload |
| POST | `/api/projects/<name>/rank` | Save media ranking |
| GET | `/api/projects/<name>/files/<filename>` | Serve a media file |
| GET | `/api/projects/<name>/files/<filename>/download` | Download a media file |
| GET | `/api/projects/<name>/files/<filename>/exif` | Get EXIF data for an image |
| DELETE | `/api/projects/<name>/files/<filename>` | Delete a media file |
| GET | `/api/projects/<name>/thumbs/<filename>` | Serve a thumbnail image |
| PUT | `/api/projects/<name>/media/<filename>/tags` | Update tags for a media file |
| PUT | `/api/projects/<name>/media/<filename>/comment` | Update comment for a media file |
| POST | `/api/projects/<name>/batch-tags` | Batch update tags for multiple files |
| DELETE | `/api/projects/<name>/batch-delete` | Batch delete multiple files |
| POST | `/api/projects/<name>/download-selected` | Download selected files as ZIP |
| GET | `/api/projects/<name>/download` | Download entire project as ZIP |
| GET | `/api/projects/<name>/export` | Export project data (JSON or CSV) |
| GET | `/api/projects/<name>/tags` | Get all unique tags used in a project |
| POST | `/api/projects/<name>/generate-thumbnails` | Generate thumbnails for existing images |
| GET | `/api/all-media` | Get all media from all projects combined |
| GET | `/manifest.json` | PWA manifest |
| GET | `/sw.js` | Service worker for PWA |

## Project Structure

```
bestshot/
├── app/
│   ├── __init__.py
│   └── main.py              # Flask application
├── static/
│   ├── app.js               # Frontend JavaScript
│   ├── styles.css           # Styles
│   ├── manifest.json        # PWA manifest
│   └── sw.js                # Service worker
├── templates/
│   └── index.html           # Main HTML template
├── docker-compose.yml       # Docker Compose config
├── Dockerfile               # Docker build file
├── requirements.txt         # Python dependencies
└── README.md
```

## Data Storage

- Rankings are stored in `.ranking.json` files within each project folder
- Project metadata is stored in `.project.json` files
- Media metadata (tags, comments, hashes) is stored in `.media-meta.json` files
- Thumbnails are stored in `.thumbs/` directories within each project folder
- Images and videos are served directly from the project folders

## Production Deployment

For production use, the Docker image runs with Gunicorn (4 workers) instead of Flask's development server:

```bash
docker-compose up -d
```

Or manually:

```bash
gunicorn -b 0.0.0.0:18473 -w 4 --timeout 120 app.main:app
```

## License

MIT License - see LICENSE file for details.
