#!/bin/bash

#######################################################
# CodeProject.AI Server Installation Script
# Target: Ubuntu 20.04 on Proxmox VM
# Modules: ALPR + Face Detection
# Author: Auto-generated installation script
#######################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
CPAI_VERSION="2.9.5"
CPAI_DOWNLOAD_URL="https://www.codeproject.com/ai/latest.aspx?type=server&os=linux&arch=x64"
INSTALL_DIR="/opt/codeproject-ai"
SERVICE_NAME="CodeProject.AI"

# Log function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root (use sudo)"
fi

log "Starting CodeProject.AI Server installation on Ubuntu 20.04..."

#######################################################
# 1. System Update and Dependencies
#######################################################
log "Updating system packages..."
apt-get update
apt-get upgrade -y

log "Installing required dependencies..."
apt-get install -y \
    wget \
    curl \
    git \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential \
    libssl-dev \
    libffi-dev \
    libjpeg-dev \
    libpng-dev \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgdiplus \
    libc6-dev \
    libgcc-s1 \
    libgssapi-krb5-2 \
    libicu66 \
    liblttng-ust0 \
    libstdc++6 \
    zlib1g

#######################################################
# 2. Install .NET Runtime (Required for CodeProject.AI)
#######################################################
log "Installing .NET 8.0 SDK and Runtime..."

# Add Microsoft package repository for Ubuntu 20.04
wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

apt-get update
apt-get install -y dotnet-sdk-8.0 dotnet-runtime-8.0 aspnetcore-runtime-8.0

# Verify .NET installation
if ! command -v dotnet &> /dev/null; then
    error ".NET installation failed"
fi

log ".NET version installed: $(dotnet --version)"

#######################################################
# 3. Download and Install CodeProject.AI Server
#######################################################
log "Downloading CodeProject.AI Server..."

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download the latest version
wget -O codeproject-ai-server.zip \
    "https://github.com/codeproject/CodeProject.AI-Server/releases/download/v${CPAI_VERSION}/CodeProject.AI-Server-Linux-x64-${CPAI_VERSION}.zip" \
    || error "Failed to download CodeProject.AI Server"

log "Extracting CodeProject.AI Server..."
unzip -q codeproject-ai-server.zip -d codeproject-ai
chmod -R 755 codeproject-ai

# Move to installation directory
mkdir -p "$INSTALL_DIR"
cp -r codeproject-ai/* "$INSTALL_DIR/"
cd "$INSTALL_DIR"

# Set permissions
chmod +x "$INSTALL_DIR/CodeProject.AI.Server"

log "CodeProject.AI Server installed to $INSTALL_DIR"

#######################################################
# 4. Create systemd service
#######################################################
log "Creating systemd service..."

cat > /etc/systemd/system/codeproject-ai.service <<EOF
[Unit]
Description=CodeProject.AI Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/CodeProject.AI.Server
Restart=on-failure
RestartSec=10
Environment="ASPNETCORE_ENVIRONMENT=Production"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable codeproject-ai.service

#######################################################
# 5. Start CodeProject.AI Server temporarily
#######################################################
log "Starting CodeProject.AI Server..."
systemctl start codeproject-ai.service

# Wait for server to start
log "Waiting for server to initialize (30 seconds)..."
sleep 30

# Check if server is running
if ! systemctl is-active --quiet codeproject-ai.service; then
    warning "Server may not have started correctly. Check logs with: journalctl -u codeproject-ai.service"
fi

#######################################################
# 6. Install ALPR Module
#######################################################
log "Installing ALPR (Automatic License Plate Recognition) module..."

ALPR_MODULE_DIR="$INSTALL_DIR/modules/ALPR"
mkdir -p "$ALPR_MODULE_DIR"

# Download ALPR module
cd "$TEMP_DIR"
wget -O alpr-module.zip \
    "https://github.com/codeproject/CodeProject.AI-ALPR/archive/refs/heads/main.zip" \
    || warning "Failed to download ALPR module from GitHub"

if [ -f alpr-module.zip ]; then
    unzip -q alpr-module.zip
    cp -r CodeProject.AI-ALPR-main/* "$ALPR_MODULE_DIR/"
    
    # Run module setup
    cd "$ALPR_MODULE_DIR"
    if [ -f "install.sh" ]; then
        bash install.sh || warning "ALPR module setup script failed"
    fi
fi

log "ALPR module installation completed"

#######################################################
# 7. Install Face Processing Module
#######################################################
log "Installing Face Detection module..."

FACE_MODULE_DIR="$INSTALL_DIR/modules/FaceProcessing"
mkdir -p "$FACE_MODULE_DIR"

# Download Face Processing module
cd "$TEMP_DIR"
wget -O face-module.zip \
    "https://github.com/codeproject/CodeProject.AI-FaceProcessing/archive/refs/heads/main.zip" \
    || warning "Failed to download Face Processing module from GitHub"

if [ -f face-module.zip ]; then
    unzip -q face-module.zip
    cp -r CodeProject.AI-FaceProcessing-main/* "$FACE_MODULE_DIR/"
    
    # Run module setup
    cd "$FACE_MODULE_DIR"
    if [ -f "install.sh" ]; then
        bash install.sh || warning "Face Processing module setup script failed"
    fi
fi

log "Face Detection module installation completed"

#######################################################
# 8. Configure Firewall (Optional)
#######################################################
log "Configuring firewall rules..."
if command -v ufw &> /dev/null; then
    ufw allow 32168/tcp comment 'CodeProject.AI Server'
    log "Firewall rule added for port 32168"
fi

#######################################################
# 9. Restart Service with Modules
#######################################################
log "Restarting CodeProject.AI Server with modules..."
systemctl restart codeproject-ai.service
sleep 10

#######################################################
# 10. Cleanup
#######################################################
log "Cleaning up temporary files..."
cd /
rm -rf "$TEMP_DIR"

#######################################################
# Installation Complete - Display Summary
#######################################################

# Clear screen
clear

# Display completion box
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}          ${GREEN}CodeProject.AI Installation Complete!${NC}          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Server URL: http://$(hostname -I | awk '{print $1}'):32168"
echo "Dashboard: http://$(hostname -I | awk '{print $1}'):32168"
echo ""
echo "Installed modules:"
echo "  - ALPR (Automatic License Plate Recognition)"
echo "  - Face Detection & Recognition"
echo ""
echo "Service management:"
echo "  Start:   sudo systemctl start codeproject-ai"
echo "  Stop:    sudo systemctl stop codeproject-ai"
echo "  Status:  sudo systemctl status codeproject-ai"
echo "  Logs:    sudo journalctl -u codeproject-ai -f"
echo ""
echo "Installation directory: $INSTALL_DIR"
echo ""
echo ""

# Display branding box
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                           N A O                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                           SIIC                           ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}              Comando Territorial de Aveiro               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
