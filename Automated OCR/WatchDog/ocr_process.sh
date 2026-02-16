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