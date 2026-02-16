#!/bin/bash
#
# Installation script for Markdown File Classifier
# Run with: sudo bash install_classifier.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/markdown_classifier"
SERVICE_USER="petr"
SERVICE_GROUP="petr"

echo "=========================================="
echo "Markdown File Classifier Installer"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Install dependencies
echo ""
echo "[1/6] Installing Python dependencies..."
apt-get update
apt-get install -y python3 python3-pip python3-venv

# Create installation directory
echo ""
echo "[2/6] Creating installation directory..."
mkdir -p "$INSTALL_DIR"
mkdir -p /var/log

# Create virtual environment
echo ""
echo "[3/6] Setting up Python virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"

# Install Python packages
echo ""
echo "[4/6] Installing Python packages..."
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install openai watchdog

# Copy the main script
echo ""
echo "[5/6] Copying script files..."
cp "$SCRIPT_DIR/markdown_classifier.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/.env.example" "$INSTALL_DIR/.env" 2>/dev/null || true

# Set permissions
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/markdown_classifier.py"

# Create systemd service file
echo ""
echo "[6/6] Creating systemd service..."
cat > /etc/systemd/system/markdown-classifier.service << EOF
[Unit]
Description=Markdown File Classifier Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$INSTALL_DIR
Environment="LLM_PROVIDER=groq"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/markdown_classifier.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

echo ""
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Edit the configuration file to add your API key:"
echo "   sudo nano $INSTALL_DIR/.env"
echo ""
echo "   Add one of the following (depending on your provider):"
echo "   GROQ_API_KEY=your-api-key-here"
echo "   OPENROUTER_API_KEY=your-api-key-here"
echo "   OPENAI_API_KEY=your-api-key-here"
echo ""
echo "2. Optionally change the LLM provider by editing:"
echo "   sudo nano /etc/systemd/system/markdown-classifier.service"
echo "   Change LLM_PROVIDER to: groq, openrouter, or openai"
echo ""
echo "3. Start the service:"
echo "   sudo systemctl start markdown-classifier"
echo ""
echo "4. Enable auto-start on boot:"
echo "   sudo systemctl enable markdown-classifier"
echo ""
echo "5. Check logs:"
echo "   tail -f /var/log/markdown_classifier.log"
echo "   OR"
echo "   journalctl -u markdown-classifier -f"
echo ""
