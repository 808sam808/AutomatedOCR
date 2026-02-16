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