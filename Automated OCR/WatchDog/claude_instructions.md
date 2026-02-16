# OCR Watch System for Ubuntu Server

## Project Structure

```
/home/petr/OCR/
├── watch_folder/          # Drop images here
├── notes/                 # OCR results go here
├── ocr_watcher.py         # Python watchdog script
└── ocr_process.sh         # Bash OCR script
```

---

## 1. Python Watchdog Script

```python
#!/usr/bin/env python3
"""
ocr_watcher.py
Monitors a folder for new images and triggers OCR processing via a bash script.
"""

import time
import os
import subprocess
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# --- Configuration ---
WATCH_FOLDER = "/home/petr/OCR/watch_folder/"
BASH_SCRIPT = "/home/petr/OCR/ocr_process.sh"
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".tif", ".webp"}
STABLE_WAIT_SECONDS = 2        # seconds between size checks
STABLE_CHECK_ATTEMPTS = 5      # how many consecutive stable checks before proceeding
LOG_FILE = "/home/petr/OCR/ocr_watcher.log"


# --- Logging Setup ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


def wait_for_stable_file(file_path: str) -> bool:
    """
    Wait until the file size stops changing, indicating the upload/copy is complete.
    Returns True if the file is stable and ready, False if it disappeared or failed.
    """
    logger.info(f"Waiting for file to finish writing: {file_path}")
    previous_size = -1
    stable_count = 0

    for _ in range(STABLE_CHECK_ATTEMPTS * 10):  # generous upper bound
        if not os.path.exists(file_path):
            logger.warning(f"File disappeared while waiting: {file_path}")
            return False

        current_size = os.path.getsize(file_path)

        if current_size == previous_size and current_size > 0:
            stable_count += 1
            if stable_count >= STABLE_CHECK_ATTEMPTS:
                logger.info(
                    f"File is stable ({current_size} bytes, "
                    f"steady for {STABLE_CHECK_ATTEMPTS * STABLE_WAIT_SECONDS}s): {file_path}"
                )
                return True
        else:
            stable_count = 0

        previous_size = current_size
        time.sleep(STABLE_WAIT_SECONDS)

    logger.warning(f"Timed out waiting for file to stabilize: {file_path}")
    return False


class ImageHandler(FileSystemEventHandler):
    """Handles file system events — specifically new image files."""

    def __init__(self):
        super().__init__()
        self.processed_files = set()

    def on_created(self, event):
        """Triggered when a new file appears in the watched folder."""
        if event.is_directory:
            return

        file_path = event.src_path
        file_ext = os.path.splitext(file_path)[1].lower()

        # Ignore non-image files
        if file_ext not in IMAGE_EXTENSIONS:
            logger.debug(f"Ignoring non-image file: {file_path}")
            return

        # Ignore files we already processed (guards against duplicate events)
        if file_path in self.processed_files:
            logger.debug(f"Already processed, skipping: {file_path}")
            return

        logger.info(f"New image detected: {file_path}")

        # Wait until the file is fully written
        if not wait_for_stable_file(file_path):
            logger.error(f"Skipping unstable/missing file: {file_path}")
            return

        # Mark as processed before running the script
        self.processed_files.add(file_path)

        # Trigger the bash OCR script
        self.run_ocr_script(file_path)

    def on_moved(self, event):
        """Handles files moved/renamed into the watched folder."""
        if event.is_directory:
            return

        file_path = event.dest_path
        file_ext = os.path.splitext(file_path)[1].lower()

        if file_ext not in IMAGE_EXTENSIONS:
            return

        if file_path in self.processed_files:
            return

        logger.info(f"Image moved into folder: {file_path}")

        if not wait_for_stable_file(file_path):
            logger.error(f"Skipping unstable/missing file: {file_path}")
            return

        self.processed_files.add(file_path)
        self.run_ocr_script(file_path)

    def run_ocr_script(self, file_path: str):
        """Calls the bash script with the image path as an argument."""
        logger.info(f"Running OCR script on: {file_path}")
        try:
            result = subprocess.run(
                ["bash", BASH_SCRIPT, file_path],
                capture_output=True,
                text=True,
                timeout=300  # 5-minute timeout for large images / slow models
            )

            if result.returncode == 0:
                logger.info(f"OCR script succeeded for: {file_path}")
                if result.stdout.strip():
                    logger.info(f"Script output: {result.stdout.strip()}")
            else:
                logger.error(f"OCR script failed for: {file_path}")
                logger.error(f"Return code: {result.returncode}")
                if result.stderr.strip():
                    logger.error(f"Script stderr: {result.stderr.strip()}")

        except subprocess.TimeoutExpired:
            logger.error(f"OCR script timed out for: {file_path}")
        except Exception as e:
            logger.error(f"Error running OCR script for {file_path}: {e}")


def main():
    """Main entry point — sets up the observer and starts watching."""
    # Ensure directories exist
    os.makedirs(WATCH_FOLDER, exist_ok=True)
    os.makedirs("/home/petr/OCR/notes/", exist_ok=True)

    logger.info("=" * 60)
    logger.info("OCR Watcher starting up")
    logger.info(f"  Watching:      {WATCH_FOLDER}")
    logger.info(f"  Script:        {BASH_SCRIPT}")
    logger.info(f"  Extensions:    {IMAGE_EXTENSIONS}")
    logger.info("=" * 60)

    event_handler = ImageHandler()
    observer = Observer()
    observer.schedule(event_handler, WATCH_FOLDER, recursive=False)
    observer.start()

    logger.info("Observer started. Waiting for images...")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("Shutdown requested by user.")
        observer.stop()

    observer.join()
    logger.info("OCR Watcher stopped.")


if __name__ == "__main__":
    main()
```

---

## 2. Bash OCR Script

```bash
#!/bin/bash
#
# ocr_process.sh
# Takes an image file path, sends it to Ollama's glm-ocr model, and saves
# the recognized text as a Markdown file.
#

set -euo pipefail

# ──────────────────────────────────────────────
#  Configuration
# ──────────────────────────────────────────────
MODEL="glm-ocr:q8_0"
OLLAMA_URL="http://localhost:11434/api/generate"
OUTPUT_DIR="/home/petr/OCR/notes/"

# ──────────────────────────────────────────────
#  1.  Validate input
# ──────────────────────────────────────────────
FILE_PATH="$1"

if [ -z "$FILE_PATH" ]; then
    echo "Usage: $0 <image_file_path>"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found: $FILE_PATH"
    exit 1
fi

# Make sure the output directory exists
mkdir -p "$OUTPUT_DIR"

# ──────────────────────────────────────────────
#  2.  Derive output filename
# ──────────────────────────────────────────────
FILENAME=$(basename "$FILE_PATH")
BASENAME="${FILENAME%.*}"

# Add a timestamp so re-uploads of the same name don't overwrite
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="${OUTPUT_DIR}${BASENAME}_${TIMESTAMP}.md"

# ──────────────────────────────────────────────
#  3.  Encode image to Base64
# ──────────────────────────────────────────────
echo "Encoding image to Base64..."
IMAGE_BASE64=$(base64 -w 0 "$FILE_PATH")

# ──────────────────────────────────────────────
#  4.  Build prompt
# ──────────────────────────────────────────────
PROMPT_TEXT="Text Recognition: ${FILENAME}"

# ──────────────────────────────────────────────
#  5.  Call Ollama API
# ──────────────────────────────────────────────
echo "Calling Ollama (model: $MODEL)..."

RESPONSE=$(curl -s --max-time 300 "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "model": "$MODEL",
  "prompt": "$PROMPT_TEXT",
  "images": ["$IMAGE_BASE64"],
  "stream": false
}
EOF
)

# ──────────────────────────────────────────────
#  6.  Check for errors & extract text
# ──────────────────────────────────────────────
if [ -z "$RESPONSE" ]; then
    echo "Error: Empty response from Ollama. Is the server running?"
    exit 1
fi

# Check if jq is available
if ! command -v jq &>/dev/null; then
    echo "Error: 'jq' is not installed. Install it with:  sudo apt install jq"
    exit 1
fi

# Check for an error field in the response
ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // empty')
if [ -n "$ERROR_MSG" ]; then
    echo "Error from Ollama API: $ERROR_MSG"
    exit 1
fi

TEXT_CONTENT=$(echo "$RESPONSE" | jq -r '.response')

if [ -z "$TEXT_CONTENT" ] || [ "$TEXT_CONTENT" = "null" ]; then
    echo "Error: No text content in the API response."
    echo "Raw response: $RESPONSE"
    exit 1
fi

# ──────────────────────────────────────────────
#  7.  Write Markdown file
# ──────────────────────────────────────────────
{
    echo "# OCR: ${FILENAME}"
    echo ""
    echo "_Processed: $(date '+%Y-%m-%d %H:%M:%S')_"
    echo ""
    echo "---"
    echo ""
    echo "$TEXT_CONTENT"
} > "$OUTPUT_FILE"

echo "OCR complete. Saved to $OUTPUT_FILE"
```

---

## 3. Installation & Setup

```bash
# ── Install system dependencies ──
sudo apt update
sudo apt install -y python3 python3-pip python3-venv jq curl

# ── Create project directories ──
mkdir -p /home/petr/OCR/{watch_folder,notes}

# ── Set up Python virtual environment ──
cd /home/petr/OCR
python3 -m venv venv
source venv/bin/activate
pip install watchdog

# ── Place the scripts ──
# Copy ocr_watcher.py  →  /home/petr/OCR/ocr_watcher.py
# Copy ocr_process.sh  →  /home/petr/OCR/ocr_process.sh

# ── Make the bash script executable ──
chmod +x /home/petr/OCR/ocr_process.sh
```

---

## 4. Systemd Service (Run on Boot)

Create the service file:

```bash
sudo nano /etc/systemd/system/ocr-watcher.service
```

Paste this content:

```ini
[Unit]
Description=OCR Image Watcher Service
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=petr
Group=petr
WorkingDirectory=/home/petr/OCR
ExecStart=/home/petr/OCR/venv/bin/python3 /home/petr/OCR/ocr_watcher.py
Restart=always
RestartSec=10

# Environment
Environment=HOME=/home/petr
Environment=PATH=/home/petr/OCR/venv/bin:/usr/local/bin:/usr/bin:/bin

# Logging
StandardOutput=append:/home/petr/OCR/ocr_watcher.log
StandardError=append:/home/petr/OCR/ocr_watcher.log

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ocr-watcher.service
sudo systemctl start ocr-watcher.service

# Check status
sudo systemctl status ocr-watcher.service

# View logs
tail -f /home/petr/OCR/ocr_watcher.log
```

---

## 5. Testing

```bash
# Make sure Ollama is running with the model loaded
ollama run glm-ocr:q8_0 --keepalive 0   # preload then exit, or just let it auto-load

# Copy a test image into the watch folder
cp /path/to/test_photo.jpg /home/petr/OCR/watch_folder/

# Watch the log in real-time
tail -f /home/petr/OCR/ocr_watcher.log

# Check the output
ls -la /home/petr/OCR/notes/
cat /home/petr/OCR/notes/test_photo_*.md
```

The system will now automatically detect any image dropped into `/home/petr/OCR/watch_folder/`, wait for the upload to complete, run OCR via Ollama, and save the extracted text as a timestamped Markdown file in `/home/petr/OCR/notes/`.



# Fix: Permission Denied on Log File

The log file was created by `root` (from `sudo`) so your `petr` user can't write to it. Quick fix:

```bash
# Take ownership of the log file and the whole OCR directory
sudo chown -R petr:petr /home/petr/OCR/

# Restart the service
sudo systemctl restart ocr-watcher.service

# Check status
sudo systemctl status ocr-watcher.service
```

If it still fails, delete the old log file and let it recreate fresh:

```bash
sudo rm /home/petr/OCR/ocr_watcher.log
sudo systemctl restart ocr-watcher.service
sudo systemctl status ocr-watcher.service
```