#!/bin/bash
###############################################################################
# Environment Setup Script
# Interactive configuration wizard for .env file
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}$1${NC}"; }

INSTALL_DIR="${INSTALL_DIR:-/opt/dis-verification-genai}"
ENV_FILE="$INSTALL_DIR/.env"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "         GenAI Research - Environment Setup"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if .env already exists
if [ -f "$ENV_FILE" ]; then
    print_warning ".env file already exists"
    read -p "Do you want to reconfigure? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Configuration cancelled"
        exit 0
    fi
    # Backup existing
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Existing configuration backed up"
fi

# Start with template
if [ -f "$INSTALL_DIR/.env.template" ]; then
    cp "$INSTALL_DIR/.env.template" "$ENV_FILE"
else
    print_error "Template file not found: $INSTALL_DIR/.env.template"
    exit 1
fi

echo ""
print_header "=== API Keys Configuration ==="
echo ""

# OpenAI API Key
print_info "OpenAI API Key (for GPT-4, GPT-4o, etc.)"
read -p "Enter OpenAI API Key (press Enter to skip): " OPENAI_KEY
if [ -n "$OPENAI_KEY" ]; then
    sed -i "s/^OPENAI_API_KEY=.*/OPENAI_API_KEY=$OPENAI_KEY/" "$ENV_FILE"
    print_success "OpenAI API key configured"
else
    print_warning "OpenAI API key not configured (cloud models will not be available)"
fi

echo ""

# Ollama configuration
print_header "=== Local Model Configuration (Ollama) ==="
echo ""

if command -v ollama &> /dev/null; then
    print_success "Ollama detected"

    # Check which models to auto-pull
    print_info "Select models to auto-pull on startup:"
    echo "  1) llama3.2:1b (lightweight, 1.3 GB)"
    echo "  2) llama3.1:8b (recommended, 4.7 GB)"
    echo "  3) None (configure manually later)"
    read -p "Choice [1-3]: " MODEL_CHOICE

    case $MODEL_CHOICE in
        1)
            sed -i "s/^OLLAMA_MODELS=.*/OLLAMA_MODELS=llama3.2:1b/" "$ENV_FILE"
            print_success "Configured to auto-pull llama3.2:1b"
            ;;
        2)
            sed -i "s/^OLLAMA_MODELS=.*/OLLAMA_MODELS=llama3.1:8b/" "$ENV_FILE"
            print_success "Configured to auto-pull llama3.1:8b"
            ;;
        *)
            sed -i "s/^OLLAMA_MODELS=.*/OLLAMA_MODELS=/" "$ENV_FILE"
            print_info "No auto-pull configured"
            ;;
    esac
else
    print_warning "Ollama not installed (local models will not be available)"
    print_info "Install with: $INSTALL_DIR/scripts/install-ollama.sh"
fi

echo ""
print_header "=== Database Configuration ==="
echo ""

# Database password
print_info "PostgreSQL database password"
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)
read -p "Use generated password? (Y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Nn]$ ]]; then
    read -sp "Enter PostgreSQL password: " DB_PASSWORD
    echo ""
fi

sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" "$ENV_FILE"
sed -i "s#^DATABASE_URL=.*#DATABASE_URL=postgresql://g3nA1-user:$DB_PASSWORD@postgres:5432/rag_memory#" "$ENV_FILE"
print_success "Database password configured"

echo ""
print_header "=== Optional: LangSmith Tracing ==="
echo ""

read -p "Enable LangSmith tracing? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter LangSmith API key: " LANGSMITH_KEY
    read -p "Enter LangSmith project name: " LANGSMITH_PROJECT

    sed -i "s/^LANGCHAIN_API_KEY=.*/LANGCHAIN_API_KEY=$LANGSMITH_KEY/" "$ENV_FILE"
    sed -i "s/^LANGSMITH_PROJECT=.*/LANGSMITH_PROJECT=$LANGSMITH_PROJECT/" "$ENV_FILE"
    sed -i "s/^LANGSMITH_TRACING=.*/LANGSMITH_TRACING=true/" "$ENV_FILE"
    print_success "LangSmith tracing enabled"
else
    sed -i "s/^LANGSMITH_TRACING=.*/LANGSMITH_TRACING=false/" "$ENV_FILE"
    print_info "LangSmith tracing disabled"
fi

echo ""
print_header "=== Configuration Summary ==="
echo ""

print_success "Environment configuration completed!"
echo ""
echo "Configuration file: $ENV_FILE"
echo ""
print_info "Configured services:"
echo "  - FastAPI Backend: http://localhost:9020"
echo "  - Streamlit Web UI: http://localhost:8501"
echo "  - PostgreSQL: localhost:5432"
echo "  - ChromaDB: localhost:8000"
echo "  - Redis: localhost:6379"
if command -v ollama &> /dev/null; then
    echo "  - Ollama: http://localhost:11434"
fi

echo ""
print_info "To start the application:"
echo "  sudo systemctl start dis-verification-genai"
echo ""
print_info "To view logs:"
echo "  cd $INSTALL_DIR && docker compose logs -f"
echo ""
