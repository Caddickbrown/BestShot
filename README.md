# BestShot

An image comparison tool that ranks photos based on user selection. Designed for macOS, BestShot helps you flag, compare, and sort images (and videos) in various formats, selecting the best shots from a set.

## Features

- Side-by-side image and video comparison
- User-driven ranking & selection workflow
- Support for extensive photo and video formats, including RAW
- Face recognition and smart filtering
- Metadata extraction (EXIF)
- Integrates with system and third-party tools (ImageMagick, RawTherapee, FFmpeg, etc.)

## System Requirements

- **Platform:** macOS (Darwin)
- **Python:** 3.11+
- **Database:** SQLite
- **Package manager:** MacPorts

## Supported File Formats

- **Images:** JPEG, PNG, TIFF, BMP, WebP, HEIC
- **RAW:** CR2/CR3, NEF, ARW, DNG, RAF, ORF, RW2
- **Video:** MP4, MOV, AVI, MKV, WebM, M4V

## Python Dependencies

- Pillow (PIL) — Image processing
- OpenCV — Computer vision/image operations
- NumPy — Matrix and array operations
- InsightFace — Face recognition
- scikit-learn — Machine learning and ranking
- ONNX Runtime — ML model runtime

You may install these via pip:
```bash
pip install pillow opencv-python numpy insightface scikit-learn onnxruntime
```

## External Tools

- ExifTool — EXIF metadata extraction
- ImageMagick — Image format conversion
- RawTherapee — RAW image processing
- FFmpeg/FFprobe — Video processing
- sips (macOS built-in) — Image conversion/metadata

You can install these (where not built-in) using MacPorts:
```bash
sudo port install exiftool ImageMagick rawtherapee ffmpeg
```

## Setup

1. Install Python 3.11 and MacPorts on your macOS system.
2. Install Python dependencies:
   ```bash
   pip install pillow opencv-python numpy insightface scikit-learn onnxruntime
   ```
3. Install external tools via MacPorts:
   ```bash
   sudo port install exiftool ImageMagick rawtherapee ffmpeg
   ```
4. Clone the repository and start developing!

## Getting Started

1. Place your images and videos in the project folder.
2. Run the main tool (coming soon) to start flagging and ranking images.

> **Note:** This project is in active development. Contributions and suggestions are welcome!

## License

Specify your license (MIT, GPL, etc.) here.
