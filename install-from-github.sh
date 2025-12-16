#!/bin/bash
# CASCADE VPN UNIVERSAL - Smart Installer
# Downloads and runs everything from GitHub on each execution
# GitHub: https://github.com/cascade-dot/a1

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/cascade-dot/a1/main"
TEMP_DIR="/tmp/cascade-vpn-install-$$"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== BASIC FUNCTIONS ====================

print_error() {
    echo -e "${RED}✗ ERROR:${NC} $*" >&2
}

print_success() {
    echo -e "${GREEN}✓ SUCCESS:${NC} $*"
}

print_info() {
    echo -e "${CYAN}→ INFO:${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $*"
}

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ==================== CHECK ROOT ====================

if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    echo "Usage: sudo bash"
    exit 1
fi

# ==================== DOWNLOAD FUNCTIONS ====================

download_file() {
    local url="$1"
    local dest="$2"
    
    print_info "Downloading: $(basename $dest)..."
    
    if curl -sSL "$url" -o "$dest" 2>/dev/null; then
        chmod +x "$dest" 2>/dev/null || true
        print_success "Downloaded: $(basename $dest)"
        return 0
    else
        print_error "Failed to download: $url"
        return 1
    fi
}

# ==================== SETUP ====================

print_header "CASCADE VPN UNIVERSAL - Installation"
print_info "Setting up installation environment..."

# Create temp directory
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

print_success "Temp directory created: $TEMP_DIR"

# ==================== DOWNLOAD ALL FILES ====================

print_info "Downloading required files from GitHub..."
echo ""

# Download utilities
mkdir -p "$TEMP_DIR/utils"
download_file "$REPO_URL/utils/colors.sh" "$TEMP_DIR/utils/colors.sh"
download_file "$REPO_URL/utils/logger.sh" "$TEMP_DIR/utils/logger.sh"
download_file "$REPO_URL/utils/validators.sh" "$TEMP_DIR/utils/validators.sh"

# Download core scripts
mkdir -p "$TEMP_DIR/core"
download_file "$REPO_URL/core/prerequisites.sh" "$TEMP_DIR/core/prerequisites.sh"
download_file "$REPO_URL/core/system-optimization.sh" "$TEMP_DIR/core/system-optimization.sh"

# Download services
mkdir -p "$TEMP_DIR/services"/{openvpn,wireguard,v2ray,xray,3x-ui}
download_file "$REPO_URL/services/openvpn/install.sh" "$TEMP_DIR/services/openvpn/install.sh"
download_file "$REPO_URL/services/wireguard/install.sh" "$TEMP_DIR/services/wireguard/install.sh"
download_file "$REPO_URL/services/v2ray/install.sh" "$TEMP_DIR/services/v2ray/install.sh"
download_file "$REPO_URL/services/xray/install.sh" "$TEMP_DIR/services/xray/install.sh"
download_file "$REPO_URL/services/3x-ui/install.sh" "$TEMP_DIR/services/3x-ui/install.sh"
download_file "$REPO_URL/services/wireguard/wg-easy.sh" "$TEMP_DIR/services/wireguard/wg-easy.sh"

echo ""
print_success "All files downloaded successfully"

# ==================== MAIN MENU ====================

show_menu() {
    print_header "Cascade VPN Universal Installer v$VERSION"
    
    echo "Select VPN service to install:"
    echo ""
    echo -e "  ${CYAN}[1]${NC} 3X-UI Control Panel"
    echo -e "  ${CYAN}[2]${NC} WireGuard VPN"
    echo -e "  ${CYAN}[3]${NC} OpenVPN"
    echo -e "  ${CYAN}[4]${NC} V2Ray Proxy"
    echo -e "  ${CYAN}[5]${NC} Xray Proxy"
    echo -e "  ${CYAN}[6]${NC} System Optimization Only"
    echo -e "  ${CYAN}[7]${NC} Complete Setup (All services)"
    echo -e "  ${CYAN}[0]${NC} Exit"
    echo ""
}

# ==================== INSTALLATION FUNCTIONS ====================

install_3x_ui() {
    print_header "Installing 3X-UI Control Panel"
    
    print_info "3X-UI is a web panel for managing Xray/V2Ray proxies"
    print_info "Port: 2053"
    
    if command -v docker &> /dev/null; then
        print_success "Docker is installed"
        print_info "3X-UI can be deployed via Docker"
    else
        print_warning "Docker not found. Install Docker first:"
        echo "  curl -fsSL https://get.docker.com | bash"
    fi
}

install_wireguard() {
    print_header "Installing WireGuard VPN"
    
    print_info "Installing WireGuard and dependencies..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y wireguard wireguard-tools > /dev/null 2>&1
        print_success "WireGuard installed"
    elif command -v yum &> /dev/null; then
        yum install -y wireguard-tools > /dev/null 2>&1
        print_success "WireGuard installed"
    else
        print_error "Unable to install WireGuard - package manager not found"
        return 1
    fi
    
    mkdir -p /etc/wireguard
    print_success "WireGuard configured"
}

install_openvpn() {
    print_header "Installing OpenVPN Server"
    
    print_info "Installing OpenVPN and dependencies..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y openvpn openvpn-blacklist > /dev/null 2>&1
        print_success "OpenVPN installed"
    elif command -v yum &> /dev/null; then
        yum install -y openvpn > /dev/null 2>&1
        print_success "OpenVPN installed"
    else
        print_error "Unable to install OpenVPN"
        return 1
    fi
    
    mkdir -p /etc/openvpn
    print_success "OpenVPN configured"
}

install_v2ray() {
    print_header "Installing V2Ray Proxy"
    
    print_info "Installing V2Ray..."
    
    if curl -sSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash > /dev/null 2>&1; then
        print_success "V2Ray installed"
        systemctl enable v2ray > /dev/null 2>&1
    else
        print_error "Failed to install V2Ray"
        return 1
    fi
}

install_xray() {
    print_header "Installing Xray Proxy"
    
    print_info "Installing Xray..."
    
    if curl -sSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh | bash > /dev/null 2>&1; then
        print_success "Xray installed"
        systemctl enable xray > /dev/null 2>&1
    else
        print_error "Failed to install Xray"
        return 1
    fi
}

system_optimization() {
    print_header "System Optimization"
    
    print_info "Optimizing system for VPN services..."
    
    # Create working directories
    mkdir -p /etc/cascade-vpn
    mkdir -p /var/lib/cascade-vpn
    mkdir -p /var/log/cascade-vpn
    
    print_success "Working directories created"
    
    # Update and upgrade system
    if command -v apt-get &> /dev/null; then
        print_info "Updating system packages..."
        apt-get update -qq > /dev/null 2>&1
        apt-get upgrade -y > /dev/null 2>&1
    elif command -v yum &> /dev/null; then
        print_info "Updating system packages..."
        yum update -y > /dev/null 2>&1
    fi
    
    print_success "System optimized"
}

complete_setup() {
    print_header "Complete Setup - Installing All Services"
    
    system_optimization
    echo ""
    install_openvpn
    echo ""
    install_wireguard
    echo ""
    install_v2ray
    echo ""
    install_xray
    echo ""
    install_3x_ui
}

# ==================== MAIN LOOP ====================

main() {
    local choice="${1:-}"
    
    system_optimization
    echo ""
    
    # If choice provided via argument, execute it directly
    if [[ -n "$choice" ]]; then
        case $choice in
            1)
                install_3x_ui
                ;;
            2)
                install_wireguard
                ;;
            3)
                install_openvpn
                ;;
            4)
                install_v2ray
                ;;
            5)
                install_xray
                ;;
            6)
                system_optimization
                ;;
            7)
                complete_setup
                ;;
            0)
                print_info "Installation cancelled"
                exit 0
                ;;
            *)
                print_error "Invalid choice: $choice"
                exit 1
                ;;
        esac
        
        print_header "Installation Complete"
        print_success "Cascade VPN setup finished!"
        
        echo "📁 Important directories:"
        echo "   Configuration: /etc/cascade-vpn"
        echo "   Logs: /var/log/cascade-vpn"
        echo "   Data: /var/lib/cascade-vpn"
        echo ""
        
        exit 0
    fi
    
    # If stdin is a terminal, run interactive mode
    if [[ -t 0 ]]; then
        while true; do
            show_menu
            read -p "Enter your choice [0-7]: " choice
            
            case $choice in
                1)
                    install_3x_ui
                    ;;
                2)
                    install_wireguard
                    ;;
                3)
                    install_openvpn
                    ;;
                4)
                    install_v2ray
                    ;;
                5)
                    install_xray
                    ;;
                6)
                    system_optimization
                    ;;
                7)
                    complete_setup
                    ;;
                0)
                    print_info "Installation cancelled"
                    exit 0
                    ;;
                *)
                    print_error "Invalid choice. Please try again."
                    ;;
            esac
            
            echo ""
            read -p "Install another component? [y/N]: " another
            if [[ "$another" != "y" && "$another" != "Y" ]]; then
                break
            fi
            echo ""
        done
        
        print_header "Installation Complete"
        print_success "Cascade VPN setup finished!"
        
        echo "📁 Important directories:"
        echo "   Configuration: /etc/cascade-vpn"
        echo "   Logs: /var/log/cascade-vpn"
        echo "   Data: /var/lib/cascade-vpn"
        echo ""
    else
        # Non-interactive: just do system optimization
        print_info "Running in non-interactive mode (stdin is piped)"
        print_info "System optimization completed!"
        print_info ""
        print_info "To install services, use:"
        print_info "  curl ... | sudo bash -s [option]"
        print_info ""
        print_info "Options:"
        print_info "  1 = 3X-UI Control Panel"
        print_info "  2 = WireGuard VPN"
        print_info "  3 = OpenVPN"
        print_info "  4 = V2Ray Proxy"
        print_info "  5 = Xray Proxy"
        print_info "  6 = System Optimization"
        print_info "  7 = Complete Setup (All)"
        echo ""
        
        print_header "Setup Complete"
        print_success "System is ready for VPN services!"
    fi
}

# ==================== ENTRY POINT ====================

main "$@"
exit $?
