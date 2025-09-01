#!/bin/bash

# WVPN Installation and Update Script
# This script handles fresh installation and updates of wvpn service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WVPN_DIR="/home/wvpn"
SERVICE_NAME="wvpn"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
REPO_URL="https://github.com/lokidv/wvpn_n.git"
PASSWORD_DIR="/etc/wvpn"
PASSWORD_FILE="$PASSWORD_DIR/server.pass"
DEFAULT_API_PASSWORD="fdk3DSfe!@#fkdixkeKK"
# Resolve node binary dynamically (fallback to /usr/bin/node)
NODE_BIN="$(command -v node || echo /usr/bin/node)"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to install Node.js prerequisites
install_nodejs() {
    print_status "Installing Node.js prerequisites..."
    
    # Update package list
    apt-get update
    
    # Install required packages
    apt-get install -y ca-certificates curl gnupg
    
    # Create keyrings directory
    mkdir -p /etc/apt/keyrings
    
    # Add NodeSource GPG key
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    
    # Add NodeSource repository
    NODE_MAJOR=20
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
    
    # Update package list and install Node.js
    apt-get update
    apt-get install nodejs -y
    
    print_success "Node.js installed successfully"
    node --version
    npm --version
}

# Function to check if Node.js is installed
check_nodejs() {
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        print_status "Node.js is already installed"
        node --version
        npm --version
        return 0
    else
        print_warning "Node.js not found, installing..."
        install_nodejs
        return 1
    fi
}

# Function to install required npm packages
install_npm_packages() {
    print_status "Installing required npm packages..."
    
    cd "$WVPN_DIR"
    
    # Install packages from package.json if it exists
    if [ -f package.json ]; then
        print_status "Installing packages from package.json..."
        if [ -f package-lock.json ]; then
            npm ci
        else
            npm install
        fi
    else
        print_warning "package.json not found, installing packages manually..."
        # Install packages globally to avoid permission issues
        npm install -g logger shelljs sleep-promise tronweb bcrypt
        
        # Create basic package.json
        npm init -y
        npm install logger shelljs sleep-promise tronweb bcrypt
    fi
    
    print_success "NPM packages installed successfully"
}

# Function to clone from GitHub and setup wvpn files
setup_wvpn_files() {
    print_status "Setting up wvpn files..."
    
    # If this script is run remotely, clone from GitHub
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [ ! -f "$SCRIPT_DIR/main.js" ]; then
        print_status "Cloning wvpn from GitHub..."
        
        # Install git if not present
        if ! command -v git &> /dev/null; then
            print_status "Installing git..."
            apt-get update
            apt-get install -y git
        fi
        
        # Create temporary directory for cloning
        TEMP_DIR="/tmp/wvpn_install_$(date +%s)"
        mkdir -p "$TEMP_DIR"
        
        # Clone the repository
        git clone "$REPO_URL" "$TEMP_DIR"
        
        # Find the actual directory name after cloning
        CLONED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "*" ! -path "$TEMP_DIR" | head -1)
        
        if [ -z "$CLONED_DIR" ]; then
            print_error "Failed to find cloned directory"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        
        print_status "Found cloned directory: $CLONED_DIR"
        
        # Copy files from cloned directory to /home/wvpn
        print_status "Copying files to $WVPN_DIR..."
        
        # Remove old installation if exists
        if [ -d "$WVPN_DIR" ]; then
            print_status "Removing old wvpn installation..."
            rm -rf "$WVPN_DIR"
        fi
        
        # Create wvpn directory
        mkdir -p "$WVPN_DIR"
        
        # Copy all files from cloned directory
        cp -r "$CLONED_DIR"/* "$WVPN_DIR/"

        # Normalize line endings for shell scripts (handle Windows CRLF)
        print_status "Normalizing line endings for shell scripts..."
        find "$WVPN_DIR" -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
        sed -i 's/\r$//' "$WVPN_DIR/main.js" 2>/dev/null || true
        
        # Clean up temporary directory
        rm -rf "$TEMP_DIR"
        
        print_success "Files cloned and copied successfully"
    else
        print_status "Running from local directory, copying all files..."
        
        # Create wvpn directory if it doesn't exist
        mkdir -p "$WVPN_DIR"
        
        # Prefer rsync for clean sync; fallback to cp -r
        if command -v rsync >/dev/null 2>&1; then
            print_status "Using rsync to sync files to $WVPN_DIR (excluding .git)..."
            rsync -a --delete --exclude '.git' --exclude 'node_modules' "$SCRIPT_DIR/" "$WVPN_DIR/"
        else
            print_warning "rsync not found, using cp -r (may leave old files)"
            cp -r "$SCRIPT_DIR"/* "$WVPN_DIR/"
        fi
        
        # Normalize line endings for shell scripts (handle Windows CRLF)
        print_status "Normalizing line endings for shell scripts..."
        find "$WVPN_DIR" -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
        sed -i 's/\r$//' "$WVPN_DIR/main.js" 2>/dev/null || true

        # Ensure scripts are executable
        chmod +x "$WVPN_DIR"/*.sh 2>/dev/null || true
        chmod +x "$WVPN_DIR/main.js" 2>/dev/null || true
        
        print_success "Files copied successfully"
    fi
    
    # Set proper permissions
    chown -R root:root "$WVPN_DIR"
    chmod +x "$WVPN_DIR/main.js" 2>/dev/null || true
}

# Function to create systemd service
create_service() {
    print_status "Creating systemd service..."
    print_status "Using node binary: $NODE_BIN"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=WVPN Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WVPN_DIR
ExecStart=$NODE_BIN $WVPN_DIR/main.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Logging
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=wvpn

[Install]
WantedBy=multi-user.target
EOF

    print_success "Systemd service created"
}

# Function to manage service
manage_service() {
    print_status "Managing wvpn service..."
    
    # Reload systemd
    systemctl daemon-reload
    
    # Stop service if running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_status "Stopping existing wvpn service..."
        systemctl stop "$SERVICE_NAME"
    fi
    
    # Enable and start service
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    
    # Check service status
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "WVPN service started successfully"
        systemctl status "$SERVICE_NAME" --no-pager -l
    else
        print_error "Failed to start wvpn service"
        systemctl status "$SERVICE_NAME" --no-pager -l
        exit 1
    fi
}

# Function to create password directory
setup_password_directory() {
    print_status "Setting up password directory..."
    mkdir -p "$PASSWORD_DIR"
    chown root:root "$PASSWORD_DIR"
    chmod 700 "$PASSWORD_DIR"
    print_success "Password directory created"
}

# Function to write default API password to file (create if missing or overwrite)
configure_api_password() {
    print_status "Configuring API password..."
    echo -n "$DEFAULT_API_PASSWORD" > "$PASSWORD_FILE"
    chown root:root "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
    print_success "Password saved to $PASSWORD_FILE"
}

# Function to show service information
show_service_info() {
    print_success "=== WVPN Installation Complete ==="
    echo ""
    echo "Service Status:"
    systemctl status "$SERVICE_NAME" --no-pager -l
    echo ""
    echo "Useful Commands:"
    echo "  Start service:   systemctl start $SERVICE_NAME"
    echo "  Stop service:    systemctl stop $SERVICE_NAME"
    echo "  Restart service: systemctl restart $SERVICE_NAME"
    echo "  View logs:       journalctl -u $SERVICE_NAME -f"
    echo "  Service status:  systemctl status $SERVICE_NAME"
    echo ""
    echo "Configuration:"
    echo "  Service file:    $SERVICE_FILE"
    echo "  Working dir:     $WVPN_DIR"
    echo "  Password dir:    /etc/wvpn/"
    echo ""
    echo "Default API Password: fdk3DSfe!@#fkdixkeKK"
    echo "Change password endpoint: http://localhost:4000/admin-change-password?newPassword=NEWPASS"
    echo "(Use header: x-current-password: CURRENTPASS)"
}

# Main installation function
main() {
    print_status "Starting WVPN installation/update process..."
    
    # Check if running as root
    check_root
    
    # Check and install Node.js if needed
    check_nodejs
    
    # Setup wvpn files
    setup_wvpn_files
    
    # Install npm packages
    install_npm_packages
    
    # Setup password directory
    setup_password_directory
    
    # Configure default API password
    configure_api_password
    
    # Create systemd service
    create_service
    
    # Start/restart service
    manage_service
    
    # Explicitly restart service to ensure password file is loaded
    print_status "Restarting service to apply API password..."
    systemctl restart "$SERVICE_NAME"
    
    # Show status after restart
    systemctl status "$SERVICE_NAME" --no-pager -l
    
    # Show final information
    show_service_info
    
    print_success "WVPN installation/update completed successfully!"
}

# Run main function
main "$@"
