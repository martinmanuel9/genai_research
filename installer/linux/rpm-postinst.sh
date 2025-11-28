#!/bin/bash
###############################################################################
# Post-installation script for GenAI Research (RHEL/CentOS/Fedora)
###############################################################################

set -e

INSTALL_DIR="/opt/genai_research"
DATA_DIR="/var/lib/genai_research"
SERVICE_USER="genai"

# Create service user if it doesn't exist
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /bin/false -d "$DATA_DIR" -c "GenAI Research Service" "$SERVICE_USER"
fi

# Create data directory
mkdir -p "$DATA_DIR"/{data,logs,stored_images}
chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
chmod 750 "$DATA_DIR"

# Set permissions on install directory
chown -R root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# Add service user to docker group if docker is installed
if getent group docker > /dev/null 2>&1; then
    usermod -aG docker "$SERVICE_USER"
fi

# Create systemd service file
cat > /etc/systemd/system/genai_research.service <<'EOF'
[Unit]
Description=GenAI Research
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/genai_research
User=root
Group=root

# Load environment
EnvironmentFile=-/opt/genai_research/.env

# Build base image first, then start all services
ExecStart=/bin/bash -c '/usr/bin/docker compose build base-poetry-deps && /usr/bin/docker compose up -d'

# Stop services
ExecStop=/usr/bin/docker compose down

# Restart policy
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  GenAI Research installed successfully!"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Interactive environment setup
read -p "Run interactive environment setup now? (Y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Starting environment setup wizard..."
    INSTALL_DIR="$INSTALL_DIR" "$INSTALL_DIR/scripts/setup-env.sh"
else
    echo "Skipping environment setup. You can run it later with:"
    echo "  sudo $INSTALL_DIR/scripts/setup-env.sh"
fi

echo ""

# Ollama information
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Ollama (Local LLM Support)"
echo "════════════════════════════════════════════════════════════════"
echo ""
if command -v ollama &> /dev/null; then
    echo "[INFO] Ollama is already installed."
else
    echo "[INFO] Ollama is NOT installed."
    echo ""
    echo "To install Ollama for local model support, run:"
    echo "  curl -fsSL https://ollama.com/install.sh | sh"
fi
echo ""
echo "After installing Ollama, you must manually start the server and pull models:"
echo ""
echo "  1. Start Ollama server:"
echo "     ollama serve &"
echo ""
echo "  2. Pull models (in a new terminal or after server starts):"
echo ""
echo "     # Pull recommended text models (~9 GB)"
echo "     $INSTALL_DIR/scripts/pull-ollama-models.sh recommended"
echo ""
echo "     # Pull vision models for image understanding (~14.5 GB)"
echo "     $INSTALL_DIR/scripts/pull-ollama-models.sh vision"
echo ""
echo "     # Or auto-detect GPU and pull optimal models"
echo "     $INSTALL_DIR/scripts/pull-ollama-models.sh auto"
echo ""
echo "See $INSTALL_DIR/INSTALL.md for detailed instructions."

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Installation Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Verify installation (recommended):"
echo "     $INSTALL_DIR/scripts/verify-installation.sh"
echo ""
echo "  2. Start the services:"
echo "     sudo systemctl start genai_research"
echo ""
echo "  3. Enable auto-start on boot (optional):"
echo "     sudo systemctl enable genai_research"
echo ""
echo "  4. Access the web interface:"
echo "     http://localhost:8501"
echo ""
echo "Documentation: $INSTALL_DIR/README.md"
echo "Troubleshooting: $INSTALL_DIR/INSTALL.md"
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit 0
