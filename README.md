# BestShot

A web-based media ranking tool that helps you compare and sort photos and videos by preference. Built with Flask and vanilla JavaScript, BestShot runs in any modern web browser and works seamlessly across devices.

## Features

- **Photo and video support** — Rank both photos and videos in the same project
- **Media type filtering** — View all media, photos only, or videos only
- **Video playback** — Click to play videos in a fullscreen modal player
- **Drag-and-drop ranking** — Reorder media by dragging them (works on both desktop and mobile/tablet)
- **Cross-device sync** — Start ranking on your laptop, continue on your phone by sharing the URL
- **Project management** — Organize media into separate projects with descriptions
- **Gallery and Rank views** — Switch between ranking mode and gallery browsing
- **URL state persistence** — Bookmark or share a URL to return to the same project, view, and filter
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
   git clone <repository-url>
   cd bestshot
   ```

2. Install Python dependencies:
   ```bash
   pip install flask
   ```

3. Run the application:
   ```bash
   python app/main.py
   ```

4. Open your browser to `http://localhost:8000`

### Using Docker

You can also run BestShot in a Docker container:

```bash
docker build -t bestshot .
docker run -p 8000:8000 -v /path/to/your/images:/project bestshot
```

## Usage

### Creating a Project

1. Enter a project name in the "Create project" field
2. Optionally add a description
3. Click "Spin up"

### Adding Images

- **Drag & drop** files into the drop zone
- **Click "Browse"** to select files from your device

### Ranking Media

1. Make sure you're in **Rank** mode (toggle in the header)
2. **On desktop**: Drag cards to reorder them
3. **On mobile/tablet**: Touch and drag cards to reorder
4. Click **"Save order"** to persist your ranking

### Filtering Media

Use the media filter buttons to control what you see:
- **Both** — Show all photos and videos
- **Photos** — Show only photos
- **Videos** — Show only videos

The filter is preserved in the URL, so you can bookmark or share specific views.

### Playing Videos

- Click the play button on any video card to open the video player
- The video plays in a fullscreen modal with standard controls
- Press **Escape** or click outside to close the player

### Switching Devices

BestShot stores your current project and view mode in the URL. To continue on another device:

1. Copy the URL from your browser's address bar (e.g., `http://yourserver:8000/?project=my-photos&view=rank`)
2. Open that URL on your other device
3. Your project will be automatically selected

You can also bookmark specific projects for quick access.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8000` | Server port |
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
| POST | `/api/projects/<name>/upload` | Upload photos and videos |
| POST | `/api/projects/<name>/rank` | Save media ranking |
| GET | `/api/projects/<name>/files/<filename>` | Serve a media file |

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
- Images are served directly from the project folders

## License

MIT License - see LICENSE file for details.
