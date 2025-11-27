#!/bin/bash
###############################################################################
# Ollama Installation Script
# Installs Ollama for local model support
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "         Ollama Installation for Local Model Support"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if already installed
if command -v ollama &> /dev/null; then
    OLLAMA_VERSION=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    print_warning "Ollama is already installed (version: $OLLAMA_VERSION)"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
fi

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Linux*)
        print_info "Installing Ollama for Linux..."
        curl -fsSL https://ollama.com/install.sh | sh
        ;;
    Darwin*)
        print_info "Installing Ollama for macOS..."
        print_warning "Please download and install Ollama from: https://ollama.com/download/mac"
        print_info "Or use Homebrew: brew install ollama"
        exit 0
        ;;
    *)
        print_error "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Configure Ollama to listen on all interfaces (for Docker access)
print_info "Configuring Ollama for Docker access..."
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama

# Wait for Ollama to start with extended retry logic (GPU initialization can take 2+ minutes)
print_info "Waiting for Ollama service to start (this may take up to 2 minutes on first run with GPU)..."
MAX_RETRIES=24
RETRY_INTERVAL=5
OLLAMA_READY=false

for i in $(seq 1 $MAX_RETRIES); do
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        OLLAMA_READY=true
        break
    fi

    # Show progress every 5 attempts
    if [ $((i % 5)) -eq 0 ]; then
        print_info "Still waiting for Ollama... ($((i * RETRY_INTERVAL)) seconds elapsed)"
    else
        echo -n "."
    fi
    sleep $RETRY_INTERVAL
done
echo ""

# Verify installation
if [ "$OLLAMA_READY" = true ]; then
    print_success "Ollama installed and running successfully!"
else
    print_warning "Ollama service is slow to start. Attempting recovery..."

    # Check if the service is at least active
    if systemctl is-active --quiet ollama; then
        print_info "Service is active but not responding. Trying to restart..."
        sudo systemctl restart ollama

        # Give it one more extended wait
        print_info "Waiting additional 30 seconds after restart..."
        for i in $(seq 1 6); do
            sleep 5
            if curl -s http://localhost:11434/api/tags &> /dev/null; then
                OLLAMA_READY=true
                print_success "Ollama is now responding!"
                break
            fi
            echo -n "."
        done
        echo ""
    fi

    # If still not ready, try running ollama serve manually in background
    if [ "$OLLAMA_READY" != true ]; then
        print_warning "Systemd service not responding. Trying manual start..."

        # Kill any existing ollama processes
        pkill -f "ollama serve" 2>/dev/null || true

        # Start ollama serve in background
        OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve > /tmp/ollama.log 2>&1 &

        # Wait for manual start
        print_info "Waiting for manual Ollama start..."
        for i in $(seq 1 12); do
            sleep 5
            if curl -s http://localhost:11434/api/tags &> /dev/null; then
                OLLAMA_READY=true
                print_success "Ollama started successfully (manual mode)!"
                print_warning "Note: Ollama is running manually. To use systemd service, reboot the system."
                break
            fi
            echo -n "."
        done
        echo ""
    fi

    if [ "$OLLAMA_READY" != true ]; then
        print_error "Ollama failed to start after all attempts"
        print_info "Check logs with: sudo journalctl -u ollama -n 50"
        print_info "Or check manual log: cat /tmp/ollama.log"
        print_info ""
        print_info "You may need to reboot and try again, or start Ollama manually:"
        echo "     ollama serve"
        exit 1
    fi
fi

echo ""
print_info "Next steps:"
echo "  1. Pull recommended models:"
echo "     /opt/genai_research/scripts/pull-ollama-models.sh auto"
echo ""
echo "  2. Or manually pull specific models:"
echo "     ollama pull llama3.1:8b"
echo ""
echo "  3. Test a model:"
echo "     ollama run llama3.1:8b"
echo ""
print_success "Ollama is ready to use!"
echo ""
