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

# Reload systemd and enable service for future boots
sudo systemctl daemon-reload
sudo systemctl enable ollama

# Stop any existing ollama processes to ensure clean start
print_info "Stopping any existing Ollama processes..."
sudo systemctl stop ollama 2>/dev/null || true
pkill -f "ollama serve" 2>/dev/null || true
sleep 2

# Start ollama serve directly (more reliable than systemd on first install)
print_info "Starting Ollama server..."
OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve > /tmp/ollama-install.log 2>&1 &
OLLAMA_PID=$!

# Wait for Ollama to start
print_info "Waiting for Ollama to initialize (this may take 30-60 seconds on first run)..."
MAX_RETRIES=24
RETRY_INTERVAL=5
OLLAMA_READY=false

for i in $(seq 1 $MAX_RETRIES); do
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        OLLAMA_READY=true
        break
    fi

    # Check if process is still running
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        print_error "Ollama process died unexpectedly"
        print_info "Check log: cat /tmp/ollama-install.log"
        break
    fi

    # Show progress every 5 attempts
    if [ $((i % 5)) -eq 0 ]; then
        print_info "Still initializing... ($((i * RETRY_INTERVAL)) seconds elapsed)"
    else
        echo -n "."
    fi
    sleep $RETRY_INTERVAL
done
echo ""

# Verify Ollama is running
if [ "$OLLAMA_READY" = true ]; then
    print_success "Ollama installed and running successfully!"

    # Now try to set up systemd to manage it going forward
    print_info "Configuring systemd service for auto-start on boot..."

    # Kill manual process and let systemd take over
    kill $OLLAMA_PID 2>/dev/null || true
    sleep 2

    # Start via systemd
    sudo systemctl start ollama

    # Verify systemd started it
    sleep 3
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        print_success "Ollama systemd service is running"
    else
        # Systemd didn't work, restart manual process
        print_warning "Systemd service not responding, keeping manual mode"
        OLLAMA_HOST=0.0.0.0:11434 nohup ollama serve > /tmp/ollama.log 2>&1 &
        sleep 3
        if curl -s http://localhost:11434/api/tags &> /dev/null; then
            print_success "Ollama running in manual mode"
            print_info "Note: After reboot, you may need to run: ollama serve"
        fi
    fi
else
    print_error "Ollama failed to start"
    print_info "Check log: cat /tmp/ollama-install.log"
    print_info ""
    print_info "Try starting manually:"
    echo "     ollama serve"
    exit 1
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
