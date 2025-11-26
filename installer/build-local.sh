#!/bin/bash
###############################################################################
# Local Installer Build Script
# Builds installers for testing before pushing to GitHub
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$PROJECT_ROOT/VERSION")

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "         GenAI Research - Local Build Script"
echo "         Version: $VERSION"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Parse arguments
BUILD_TARGET="${1:-all}"

build_linux_deb() {
    print_info "Building Linux DEB package..."

    local PKG_DIR="genai-research_${VERSION}_amd64"
    local BUILD_DIR="$PROJECT_ROOT/build/deb"

    # Clean previous build
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Create package structure
    mkdir -p "$BUILD_DIR/$PKG_DIR/opt/genai-research"
    mkdir -p "$BUILD_DIR/$PKG_DIR/DEBIAN"

    # Copy application files
    print_info "Copying application files..."

    # Verify source files exist before copying
    for file in src scripts docker-compose.yml .env.template VERSION CHANGELOG.md README.md INSTALL.md; do
        if [ ! -e "$PROJECT_ROOT/$file" ]; then
            print_error "Missing required file/directory: $file"
            exit 1
        fi
    done

    # Verify critical scripts exist
    for script in setup-env.sh install-ollama.sh pull-ollama-models.sh verify-installation.sh; do
        if [ ! -f "$PROJECT_ROOT/scripts/$script" ]; then
            print_error "Missing required script: scripts/$script"
            exit 1
        fi
    done

    # Copy with verification
    cp -r "$PROJECT_ROOT/src" "$BUILD_DIR/$PKG_DIR/opt/genai-research/" || { print_error "Failed to copy src"; exit 1; }
    cp -r "$PROJECT_ROOT/scripts" "$BUILD_DIR/$PKG_DIR/opt/genai-research/" || { print_error "Failed to copy scripts"; exit 1; }
    cp "$PROJECT_ROOT/docker-compose.yml" "$BUILD_DIR/$PKG_DIR/opt/genai-research/" || { print_error "Failed to copy docker-compose.yml"; exit 1; }
    cp "$PROJECT_ROOT/.env.template" "$BUILD_DIR/$PKG_DIR/opt/genai-research/.env" || { print_error "Failed to copy .env.template"; exit 1; }
    cp "$PROJECT_ROOT/VERSION" "$BUILD_DIR/$PKG_DIR/opt/genai-research/" || { print_error "Failed to copy VERSION"; exit 1; }
    cp "$PROJECT_ROOT/CHANGELOG.md" "$BUILD_DIR/$PKG_DIR/opt/genai-research/" || { print_error "Failed to copy CHANGELOG.md"; exit 1; }
    cp "$PROJECT_ROOT/README.md" "$BUILD_DIR/$PKG_DIR/opt/genai-research/" || { print_error "Failed to copy README.md"; exit 1; }
    cp "$PROJECT_ROOT/INSTALL.md" "$BUILD_DIR/$PKG_DIR/opt/genai-research/" || { print_error "Failed to copy INSTALL.md"; exit 1; }

    # Verify all files were copied
    print_info "Verifying copied files..."
    for file in src scripts docker-compose.yml .env VERSION CHANGELOG.md README.md INSTALL.md; do
        if [ ! -e "$BUILD_DIR/$PKG_DIR/opt/genai-research/$file" ]; then
            print_error "Verification failed: $file was not copied"
            exit 1
        fi
    done
    print_success "All application files copied and verified"

    # Copy DEBIAN control files
    cp "$SCRIPT_DIR/linux/DEBIAN/"* "$BUILD_DIR/$PKG_DIR/DEBIAN/"

    # Update version in control file
    sed -i "s/VERSION_PLACEHOLDER/$VERSION/g" "$BUILD_DIR/$PKG_DIR/DEBIAN/control"

    # Set permissions
    chmod 755 "$BUILD_DIR/$PKG_DIR/DEBIAN/postinst"
    chmod 755 "$BUILD_DIR/$PKG_DIR/DEBIAN/prerm"
    chmod 755 "$BUILD_DIR/$PKG_DIR/DEBIAN/postrm"
    chmod +x "$BUILD_DIR/$PKG_DIR/opt/genai-research/scripts/"*.sh

    # Build DEB package
    print_info "Building DEB package..."
    cd "$BUILD_DIR"
    dpkg-deb --build "$PKG_DIR"

    # Move to output directory
    mkdir -p "$PROJECT_ROOT/dist"
    mv "$BUILD_DIR/${PKG_DIR}.deb" "$PROJECT_ROOT/dist/"

    print_success "DEB package built: dist/${PKG_DIR}.deb"
}

build_linux_rpm() {
    print_info "Building Linux RPM package..."

    if ! command -v rpmbuild &> /dev/null; then
        print_error "rpmbuild not found. Install with: sudo apt-get install rpm"
        return 1
    fi

    local SPEC_FILE="$SCRIPT_DIR/linux/genai-research.spec"

    # Create RPM build directories
    mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    # Create spec file
    cat > "$SPEC_FILE" <<EOF
Name:           genai-research
Version:        $VERSION
Release:        1%{?dist}
Summary:        AI-powered research and verification system
License:        Proprietary
URL:            https://github.com/martinmanuel9/genai_research
Requires:       docker >= 24.0.0

%description
GenAI Research provides comprehensive AI-powered research and
verification capabilities using advanced AI models. Features include:
- Multi-agent test plan generation with Actor-Critic system
- RAG-enhanced document analysis with citation tracking
- Test card creation with Word export
- Support for cloud LLMs (OpenAI) and local models (Ollama)
- US-based model compliance (Meta, Microsoft, Snowflake)
- Complete on-premises deployment option

%prep
# No prep needed - files come from staging

%build
# No build needed - Python/Docker application

%install
mkdir -p %{buildroot}/opt/genai-research
cp -r $PROJECT_ROOT/src %{buildroot}/opt/genai-research/
cp -r $PROJECT_ROOT/scripts %{buildroot}/opt/genai-research/
cp $PROJECT_ROOT/docker-compose.yml %{buildroot}/opt/genai-research/
cp $PROJECT_ROOT/.env.template %{buildroot}/opt/genai-research/.env
cp $PROJECT_ROOT/VERSION %{buildroot}/opt/genai-research/
cp $PROJECT_ROOT/CHANGELOG.md %{buildroot}/opt/genai-research/
cp $PROJECT_ROOT/README.md %{buildroot}/opt/genai-research/
cp $PROJECT_ROOT/INSTALL.md %{buildroot}/opt/genai-research/

%files
%defattr(-,root,root,-)
/opt/genai-research

%post
# Run post-installation script
if [ -f /opt/genai-research/scripts/rpm-postinst.sh ]; then
    bash /opt/genai-research/scripts/rpm-postinst.sh
fi

%preun
# Stop and disable service before uninstall
if systemctl is-active --quiet genai-research; then
    systemctl stop genai-research
fi
if systemctl is-enabled --quiet genai-research; then
    systemctl disable genai-research
fi

%postun
# Remove systemd service file on purge
if [ \$1 -eq 0 ]; then
    rm -f /etc/systemd/system/genai-research.service
    systemctl daemon-reload
fi

%changelog
* $(date +'%a %b %d %Y') Developer <dev@example.com> - $VERSION-1
- Release $VERSION
EOF

    # Copy RPM postinst script to project scripts (will be included in package)
    cp "$SCRIPT_DIR/linux/rpm-postinst.sh" "$PROJECT_ROOT/scripts/" 2>/dev/null || true

    # Create source tarball
    print_info "Creating source tarball..."
    cd "$PROJECT_ROOT"
    tar czf ~/rpmbuild/SOURCES/genai-research-$VERSION.tar.gz \
        --exclude='.git' \
        --exclude='build' \
        --exclude='dist' \
        --exclude='*.pyc' \
        src scripts docker-compose.yml .env.template VERSION CHANGELOG.md README.md

    # Build RPM
    print_info "Building RPM package..."
    rpmbuild -ba "$SPEC_FILE"

    # Copy to dist
    mkdir -p "$PROJECT_ROOT/dist"
    cp ~/rpmbuild/RPMS/x86_64/genai-research-$VERSION-1.*.x86_64.rpm "$PROJECT_ROOT/dist/"

    print_success "RPM package built: dist/genai-research-$VERSION-1.*.x86_64.rpm"
}

build_macos_dmg() {
    print_info "Building macOS DMG..."

    if [[ "$(uname -s)" != "Darwin" ]]; then
        print_warning "macOS builds must be done on macOS"
        return 1
    fi

    local APP_NAME="GenAI Research"
    local DMG_NAME="genai-research-$VERSION.dmg"
    local BUILD_DIR="$PROJECT_ROOT/build/macos"

    # Clean previous build
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Create app bundle
    print_info "Creating app bundle..."
    mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
    mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"

    # Copy application files
    cp -r "$PROJECT_ROOT/src" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/"
    cp -r "$PROJECT_ROOT/scripts" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/"
    cp "$PROJECT_ROOT/docker-compose.yml" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/"
    cp "$PROJECT_ROOT/.env.template" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/.env"
    cp "$PROJECT_ROOT/VERSION" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/"
    cp "$PROJECT_ROOT/CHANGELOG.md" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/"
    cp "$PROJECT_ROOT/README.md" "$BUILD_DIR/$APP_NAME.app/Contents/Resources/"

    # Create Info.plist
    cat > "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>GenAI Research</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
</dict>
</plist>
EOF

    # Create launcher script with setup
    cat > "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/launcher" <<'EOF'
#!/bin/bash
RESOURCES_DIR="$(dirname "$0")/../Resources"
cd "$RESOURCES_DIR"

# Run setup on first launch if .env doesn't exist
if [ ! -f "$RESOURCES_DIR/.env" ] || [ ! -s "$RESOURCES_DIR/.env" ]; then
    osascript -e 'tell app "Terminal" to do script "cd '"$RESOURCES_DIR"' && ./scripts/setup-env.sh"'
    exit 0
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    osascript -e 'display dialog "Docker Desktop is not running. Please start Docker Desktop first." buttons {"OK"} default button "OK"'
    open -a "Docker"
    exit 1
fi

# Start services
docker compose up -d

# Wait for services
sleep 5

# Open web interface
open http://localhost:8501
EOF
    chmod +x "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/launcher"

    # Create setup script launcher
    cat > "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/setup" <<'EOF'
#!/bin/bash
RESOURCES_DIR="$(dirname "$0")/../Resources"
cd "$RESOURCES_DIR"
osascript -e 'tell app "Terminal" to do script "cd '"$RESOURCES_DIR"' && ./scripts/setup-env.sh && exit"'
EOF
    chmod +x "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/setup"

    # Create DMG
    print_info "Creating DMG..."
    mkdir -p "$PROJECT_ROOT/dist"
    hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR" -ov -format UDZO "$PROJECT_ROOT/dist/$DMG_NAME"

    print_success "DMG created: dist/$DMG_NAME"
}

# Main build logic
case "$BUILD_TARGET" in
    deb)
        build_linux_deb
        ;;
    rpm)
        build_linux_rpm
        ;;
    dmg)
        build_macos_dmg
        ;;
    linux)
        build_linux_deb
        build_linux_rpm
        ;;
    all)
        print_info "Building all packages..."
        build_linux_deb || true
        build_linux_rpm || true
        if [[ "$(uname -s)" == "Darwin" ]]; then
            build_macos_dmg || true
        fi
        ;;
    *)
        print_error "Invalid build target: $BUILD_TARGET"
        echo ""
        echo "Usage: $0 [deb|rpm|dmg|linux|all]"
        echo ""
        echo "  deb    - Build Debian/Ubuntu package"
        echo "  rpm    - Build RHEL/CentOS/Fedora package"
        echo "  dmg    - Build macOS package (macOS only)"
        echo "  linux  - Build both DEB and RPM"
        echo "  all    - Build all available packages [default]"
        exit 1
        ;;
esac

echo ""
print_success "Build completed!"
echo ""
if [ -d "$PROJECT_ROOT/dist" ]; then
    print_info "Built packages:"
    ls -lh "$PROJECT_ROOT/dist/"
fi
echo ""
