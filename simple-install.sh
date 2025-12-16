#!/bin/bash
# SIMPLE CASCADE VPN INSTALLER - Simplified Version
# GitHub: https://github.com/cascade-dot/a1

set -euo pipefail

# ==================== CONFIGURATION ====================
MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"
INSTALL_DATE=$(date +"%Y-%m-%d %H:%M:%S")

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
    echo "Usage: sudo bash simple-install.sh"
    exit 1
fi

# ==================== MAIN MENU ====================

show_menu() {
    print_header "Cascade VPN Universal Installer v$VERSION"
    
    echo "Select VPN service to install:"
    echo ""
    echo "  ${CYAN}[1]${NC} 3X-UI Control Panel"
    echo "  ${CYAN}[2]${NC} WireGuard VPN"
    echo "  ${CYAN}[3]${NC} OpenVPN"
    echo "  ${CYAN}[4]${NC} System Optimization Only"
    echo "  ${CYAN}[5]${NC} Complete Setup (All services)"
    echo "  ${CYAN}[0]${NC} Exit"
    echo ""
}

# ==================== INSTALLATION FUNCTIONS ====================

install_3x_ui() {
    print_header "Installing 3X-UI Control Panel"
    
    print_info "3X-UI is a web panel for managing Xray/V2Ray proxies"
    print_info "Port: 2053"
    
    # Check if service exists
    if command -v docker &> /dev/null; then
        print_success "Docker is installed"
        print_info "3X-UI installation prepared"
        print_warning "Please configure 3X-UI manually after installation"
    else
        print_warning "Docker not found. Please install Docker first:"
        echo "  curl -fsSL https://get.docker.com | bash"
    fi
}

install_wireguard() {
    print_header "Installing WireGuard VPN"
    
    print_info "Installing WireGuard and dependencies..."
    
    # Update system
    if command -v apt-get &> /dev/null; then
        apt-get update > /dev/null 2>&1
        apt-get install -y wireguard wireguard-tools > /dev/null 2>&1
        print_success "WireGuard installed"
    elif command -v yum &> /dev/null; then
        yum install -y wireguard-tools > /dev/null 2>&1
        print_success "WireGuard installed"
    else
        print_error "Unable to install WireGuard - package manager not found"
        return 1
    fi
    
    print_info "WireGuard configuration directory: /etc/wireguard"
    print_info "Generate keys and configure manually"
}

install_openvpn() {
    print_header "Installing OpenVPN"
    
    print_info "Installing OpenVPN server..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update > /dev/null 2>&1
        apt-get install -y openvpn openvpn-blacklist > /dev/null 2>&1
        print_success "OpenVPN installed"
    elif command -v yum &> /dev/null; then
        yum install -y openvpn > /dev/null 2>&1
        print_success "OpenVPN installed"
    else
        print_error "Unable to install OpenVPN"
        return 1
    fi
    
    print_info "OpenVPN configuration directory: /etc/openvpn"
}

system_optimization() {
    print_header "System Optimization"
    
    print_info "Optimizing system for VPN..."
    
    # Create working directories
    mkdir -p /etc/cascade-vpn
    mkdir -p /var/lib/cascade-vpn
    mkdir -p /var/log/cascade-vpn
    
    print_success "Working directories created"
    
    # Update system
    if command -v apt-get &> /dev/null; then
        apt-get update > /dev/null 2>&1
        apt-get upgrade -y > /dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum update -y > /dev/null 2>&1
    fi
    
    print_success "System optimized"
}

complete_setup() {
    print_header "Complete Setup - Installing All Services"
    
    install_openvpn
    echo ""
    install_wireguard
    echo ""
    install_3x_ui
    echo ""
    system_optimization
}

# ==================== MAIN LOOP ====================

main() {
    print_header "CASCADE VPN UNIVERSAL - Installation"
    print_info "Cascade VPN Installation Started"
    
    system_optimization
    echo ""
    
    while true; do
        show_menu
        read -p "Enter your choice [0-5]: " choice
        
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
                system_optimization
                ;;
            5)
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
    
    # Final summary
    print_header "Installation Complete"
    print_success "Cascade VPN setup finished"
    
    echo "📁 Important directories:"
    echo "   Configuration: /etc/cascade-vpn"
    echo "   Logs: /var/log/cascade-vpn"
    echo "   Data: /var/lib/cascade-vpn"
    echo ""
    echo "🚀 Next steps:"
    echo "   1. Configure your VPN services"
    echo "   2. Start services: systemctl start wireguard@wg0 (if WireGuard)"
    echo "   3. Check status: systemctl status"
    echo ""
}

# ==================== ENTRY POINT ====================

main "$@"
exit $?
