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

# Start services
ExecStart=/usr/bin/docker compose up -d

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

# Optional: Install and configure Ollama
if ! command -v ollama &> /dev/null; then
    read -p "Install Ollama for local model support? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing Ollama..."
        "$INSTALL_DIR/scripts/install-ollama.sh"

        # Pull models if Ollama was installed successfully
        if command -v ollama &> /dev/null; then
            read -p "Pull recommended Ollama models now? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Pulling models (this may take several minutes)..."
                "$INSTALL_DIR/scripts/pull-ollama-models.sh" auto
            fi
        fi
    fi
else
    echo "Ollama is already installed."
    read -p "Pull/update Ollama models now? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$INSTALL_DIR/scripts/pull-ollama-models.sh" auto
    fi
fi

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
