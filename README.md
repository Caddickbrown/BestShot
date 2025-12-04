# BestShot

A web-based media ranking tool that helps you compare and sort photos and videos by preference. Built with Flask and vanilla JavaScript, BestShot runs in any modern web browser and works seamlessly across devices.

## Features

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

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Caddickbrown/BestShot.git
   cd BestShot
   ```

2. Install Python dependencies:
   ```bash
   pip install flask
   ```

3. Run the application:
   ```bash
   python app/main.py
   ```

4. Open your browser to `http://localhost:18473`

### Using Docker (Optional)

If you create a Dockerfile, you can run BestShot in a container:

```bash
docker build -t bestshot .
docker run -p 18473:18473 -v /path/to/your/images:/project bestshot
```

Mount your images directory to `/project` inside the container.

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

### Filtering Media

Use the media filter buttons to control what you see:
- **Both** — Show all photos and videos
- **Photos** — Show only photos
- **Videos** — Show only videos

The filter is preserved in the URL, so you can bookmark or share specific views.

### Viewing Media

- Click on any photo or video to open the fullscreen media viewer
- Use **← →** arrow keys or click the navigation arrows to browse
- Add or remove tags directly in the viewer
- Press **Escape** or click outside to close

### Tagging Media

1. Click **"+ tag"** on any photo or video card
2. Type a tag name and press **Enter**
3. Click the **×** on a tag to remove it

You can also add and remove tags in the fullscreen media viewer.

Tags are normalized to lowercase and stored per-media item.

### All Projects View

Click **"All Projects"** in the sidebar to view all media from all projects in one place. This is useful for browsing across your entire library. Note that drag-and-drop ranking is disabled in this view.

### Searching

Use the search box in the header to filter media:
- Search by **filename** (partial match)
- Search by **tag** (partial match)
- Press **Escape** or click the **×** to clear the search

Note: Drag-and-drop ranking is disabled while searching to preserve the original order.

### Deleting Media

- Click the **×** button on any photo or video card to delete it
- A confirmation dialog will appear before deletion
- Deleted files are permanently removed and cannot be recovered

### Deleting Projects

- Click the **"Delete"** button in the header while viewing a project
- A confirmation dialog will appear before deletion
- This removes all media files in the project

### Switching Devices

BestShot stores your current project and media filter in the URL. To continue on another device:

1. Copy the URL from your browser's address bar (e.g., `http://yourserver:18473/?project=my-photos&media=photos`)
2. Open that URL on your other device
3. Your project and filter settings will be automatically restored

You can also bookmark specific projects for quick access.

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
| GET | `/api/projects` | List all projects (includes photo and video counts) |
| POST | `/api/projects` | Create a new project |
| GET | `/api/projects/<name>/images?media=<filter>` | Get media for a project. Filter: `all`, `photos`, or `videos` |
| PUT | `/api/projects/<name>` | Update project description |
| DELETE | `/api/projects/<name>` | Delete a project and all its contents |
| POST | `/api/projects/<name>/upload` | Upload photos and videos |
| POST | `/api/projects/<name>/rank` | Save media ranking |
| GET | `/api/projects/<name>/files/<filename>` | Serve a media file |
| DELETE | `/api/projects/<name>/files/<filename>` | Delete a media file from a project |
| PUT | `/api/projects/<name>/media/<filename>/tags` | Update tags for a media file |
| GET | `/api/projects/<name>/tags` | Get all unique tags used in a project |
| GET | `/api/all-media?media=<filter>` | Get all media from all projects combined |

## Project Structure

```
bestshot/
├── app/
│   ├── __init__.py
│   └── main.py          # Flask application
├── static/
│   ├── app.js           # Frontend JavaScript
│   └── styles.css       # Styles
├── templates/
│   └── index.html       # Main HTML template
└── README.md
```

## Data Storage

- Rankings are stored in `.ranking.json` files within each project folder
- Project metadata is stored in `.project.json` files
- Media tags are stored in `.media-meta.json` files within each project folder
- Images and videos are served directly from the project folders

## License

MIT License - see LICENSE file for details.
