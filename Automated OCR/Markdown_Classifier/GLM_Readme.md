# Markdown File Classifier

A Python script that monitors a directory for new markdown files and uses an LLM to automatically classify them into predefined categories.

## Features

- **Real-time monitoring**: Watches for new markdown files using filesystem events
- **LLM-powered classification**: Uses AI to intelligently categorize content
- **Multiple LLM providers**: Supports Groq, OpenRouter, and OpenAI APIs
- **Automatic organization**: Moves processed files and appends content to category files
- **Systemd integration**: Run as a background service on Ubuntu Server

## Categories

The classifier sorts content into these categories:
- **Chemistry**: Chemical reactions, elements, compounds, molecular structures
- **Religion**: Religious texts, theology, spirituality, religious history
- **Math**: Mathematics, algebra, calculus, geometry, statistics
- **French**: French language learning, grammar, literature
- **Other**: Content that doesn't fit the above categories

## Installation

### Quick Install

```bash
# Download the files
cd /tmp
# (Assuming you have markdown_classifier.py, install_classifier.sh, and .env.example)

# Run the installer
sudo bash install_classifier.sh
```

### Manual Installation

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install python3 python3-pip python3-venv

# Create directory
sudo mkdir -p /opt/markdown_classifier

# Create virtual environment
python3 -m venv /opt/markdown_classifier/venv

# Install Python packages
/opt/markdown_classifier/venv/bin/pip install openai watchdog

# Copy the script
sudo cp markdown_classifier.py /opt/markdown_classifier/
sudo chmod +x /opt/markdown_classifier/markdown_classifier.py
```

## Configuration

### 1. Set up API Key

Edit the environment file:

```bash
sudo nano /opt/markdown_classifier/.env
```

Add your API key based on your chosen provider:

```bash
# For Groq (recommended - fast and free tier available)
GROQ_API_KEY=gsk_xxxxxxxxxxxxx

# For OpenRouter
OPENROUTER_API_KEY=sk-or-xxxxxxxxxxxxx

# For OpenAI
OPENAI_API_KEY=sk-xxxxxxxxxxxxx
```

### 2. Choose LLM Provider

Edit the systemd service:

```bash
sudo nano /etc/systemd/system/markdown-classifier.service
```

Change `LLM_PROVIDER` to one of:
- `groq` (default)
- `openrouter`
- `openai`

### 3. Get API Keys

- **Groq**: https://console.groq.com/ (Free tier available, fast inference)
- **OpenRouter**: https://openrouter.ai/ (Multiple models, pay-as-you-go)
- **OpenAI**: https://platform.openai.com/ (GPT models)

## Running the Service

### Start the service
```bash
sudo systemctl start markdown-classifier
```

### Enable auto-start on boot
```bash
sudo systemctl enable markdown-classifier
```

### Check status
```bash
sudo systemctl status markdown-classifier
```

### Stop the service
```bash
sudo systemctl stop markdown-classifier
```

### Restart after configuration changes
```bash
sudo systemctl daemon-reload
sudo systemctl restart markdown-classifier
```

## Monitoring Logs

### Via log file
```bash
tail -f /var/log/markdown_classifier.log
```

### Via journalctl
```bash
journalctl -u markdown-classifier -f
```

## Directory Structure

```
/home/petr/OCR/notes/
├── example.md           # New file to be classified
├── Chemistry/
│   └── chemistry.md     # Accumulated chemistry content
├── Religion/
│   └── religion.md      # Accumulated religion content
├── French/
│   └── french.md        # Accumulated French content
├── Math/
│   └── math.md          # Accumulated math content
├── Other/
│   └── other.md         # Accumulated other content
└── processed/           # Original files after processing
```

## How It Works

1. **Detection**: The script monitors `/home/petr/OCR/notes` for new `.md` files
2. **Classification**: When a new file appears, its content is sent to the LLM
3. **Categorization**: The LLM returns the best-fitting category
4. **Organization**: Content is appended to the category's markdown file
5. **Cleanup**: Original file is moved to the `processed/` directory

## Running Manually (for testing)

```bash
cd /opt/markdown_classifier
source venv/bin/activate
LLM_PROVIDER=groq GROQ_API_KEY=your-key python markdown_classifier.py
```

## Customization

### Add New Categories

Edit `CATEGORIES` list in `markdown_classifier.py`:

```python
CATEGORIES = ["Chemistry", "Religion", "Math", "French", "Other", "Physics"]
```

### Change Notes Directory

Edit `NOTES_DIR` in `markdown_classifier.py`:

```python
NOTES_DIR = "/your/custom/path"
```

### Process Existing Files

Uncomment this line in the `main()` function:

```python
scan_existing_files(client, model)
```

## Troubleshooting

### Service won't start
```bash
# Check if Python packages are installed
/opt/markdown_classifier/venv/bin/pip list

# Check logs
journalctl -u markdown-classifier -n 50
```

### API errors
- Verify your API key is correct
- Check you have API credits/quota
- Ensure correct provider is configured

### Files not being processed
- Verify the notes directory exists
- Check file permissions
- Ensure files have `.md` extension