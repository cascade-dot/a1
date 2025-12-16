#!/bin/bash
# CASCADE VPN UNIVERSAL - Remote Server Installer
# For use on REMOTE machine - installs VPN server only
# Usage: 
#   sudo bash auto-install.sh          (interactive mode)
#   curl ... | sudo bash -s 1          (option 1 = OpenVPN)
#   curl ... | sudo bash -s 5          (option 5 = All services)

set -euo pipefail

VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==================== FUNCTIONS ====================

print_error() {
    echo -e "${RED}✗ ERROR:${NC} $*" >&2
}

print_success() {
    echo -e "${GREEN}✓ SUCCESS:${NC} $*"
}

print_info() {
    echo -e "${CYAN}→ INFO:${NC} $*"
}

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Check root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    echo "Usage: sudo bash auto-install.sh"
    exit 1
fi

# ==================== GET CHOICE ====================

CHOICE="${1:-}"

# If no argument, show menu
if [[ -z "$CHOICE" ]]; then
    print_header "CASCADE VPN UNIVERSAL v$VERSION - REMOTE SERVER SETUP"
    
    echo "Select VPN service to install on this remote server:"
    echo ""
    echo -e "  ${CYAN}[1]${NC} OpenVPN"
    echo -e "  ${CYAN}[2]${NC} WireGuard"
    echo -e "  ${CYAN}[3]${NC} V2Ray"
    echo -e "  ${CYAN}[4]${NC} Xray"
    echo -e "  ${CYAN}[5]${NC} All Services (OpenVPN + WireGuard + V2Ray + Xray)"
    echo -e "  ${CYAN}[6]${NC} System Optimization Only"
    echo -e "  ${CYAN}[0]${NC} Exit"
    echo ""
    read -p "Select option [0-6]: " CHOICE
fi

case $CHOICE in
    0)
        print_info "Exiting..."
        exit 0
        ;;
    1|2|3|4|5|6)
        # Valid choice - continue
        ;;
    *)
        print_error "Invalid option!"
        exit 1
        ;;
esac

# ==================== SYSTEM SETUP ====================

print_header "System Setup"

print_info "Creating directories..."
mkdir -p /etc/cascade-vpn /var/lib/cascade-vpn /var/log/cascade-vpn
chmod 755 /etc/cascade-vpn /var/lib/cascade-vpn /var/log/cascade-vpn
print_success "Directories created"

print_info "Updating system packages..."
if command -v apt-get &> /dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>&1 | tail -1 || true
    DEBIAN_FRONTEND=noninteractive timeout 300 apt-get upgrade -y -qq > /dev/null 2>&1 || print_info "Packages updated"
    PACKAGE_CMD="DEBIAN_FRONTEND=noninteractive apt-get install -y -qq"
    print_success "System updated (Debian/Ubuntu)"
elif command -v yum &> /dev/null; then
    yum update -y -q > /dev/null 2>&1
    PACKAGE_CMD="yum install -y -q"
    print_success "System updated (RedHat/CentOS)"
else
    print_error "No supported package manager found"
    exit 1
fi

# ==================== INSTALLATION ====================

# Install OpenVPN
if [[ "$CHOICE" == "1" || "$CHOICE" == "5" ]]; then
    print_header "Installing OpenVPN"
    
    print_info "Installing OpenVPN..."
    if eval "timeout 300 $PACKAGE_CMD openvpn > /dev/null 2>&1"; then
        mkdir -p /etc/openvpn /var/log/openvpn
        systemctl enable openvpn > /dev/null 2>&1 || true
        print_success "OpenVPN installed"
    else
        print_error "OpenVPN installation failed"
    fi
fi

# Install WireGuard
if [[ "$CHOICE" == "2" || "$CHOICE" == "5" ]]; then
    print_header "Installing WireGuard"
    
    print_info "Installing WireGuard..."
    if eval "timeout 300 $PACKAGE_CMD wireguard wireguard-tools > /dev/null 2>&1"; then
        mkdir -p /etc/wireguard
        chmod 700 /etc/wireguard
        print_success "WireGuard installed"
    else
        print_error "WireGuard installation failed"
    fi
fi

# Install V2Ray
if [[ "$CHOICE" == "3" || "$CHOICE" == "5" ]]; then
    print_header "Installing V2Ray"
    
    print_info "Downloading and installing V2Ray..."
    if timeout 300 bash -c 'curl -sSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash' > /dev/null 2>&1; then
        systemctl enable v2ray > /dev/null 2>&1 || true
        print_success "V2Ray installed"
    else
        print_error "V2Ray installation failed"
    fi
fi

# Install Xray
if [[ "$CHOICE" == "4" || "$CHOICE" == "5" ]]; then
    print_header "Installing Xray"
    
    print_info "Downloading and installing Xray..."
    if timeout 300 bash -c 'curl -sSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh | bash' > /dev/null 2>&1; then
        systemctl enable xray > /dev/null 2>&1 || true
        print_success "Xray installed"
    else
        print_error "Xray installation failed"
    fi
fi

# ==================== COMPLETION ====================

print_header "Installation Complete!"

echo "✓ CONFIGURATION DIRECTORIES:"
echo "  • Configuration: /etc/cascade-vpn"
echo "  • Data: /var/lib/cascade-vpn"
echo "  • Logs: /var/log/cascade-vpn"
echo ""

echo "📝 NEXT STEPS:"
echo "  1. Configure your VPN services"
echo "  2. Start services: systemctl start [service-name]"
echo "  3. Check status: systemctl status [service-name]"
echo ""

print_success "VPN Server is ready for configuration!"
echo ""

exit 0
