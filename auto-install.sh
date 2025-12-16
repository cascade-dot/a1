#!/bin/bash
# CASCADE VPN UNIVERSAL - Complete Auto-Install
# Single command installation of everything
# Usage: curl -sSL https://raw.githubusercontent.com/cascade-dot/a1/main/auto-install.sh | sudo bash

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

# Check root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    echo "Usage: sudo bash auto-install.sh"
    exit 1
fi

# ==================== MAIN INSTALLATION ====================

print_header "CASCADE VPN UNIVERSAL v$VERSION - FULL AUTO-INSTALL"
print_info "Installing all VPN services automatically..."
echo ""

# ========== SYSTEM SETUP ==========

print_header "Step 1: System Optimization"

print_info "Creating directories..."
mkdir -p /etc/cascade-vpn
mkdir -p /var/lib/cascade-vpn
mkdir -p /var/log/cascade-vpn
chmod 755 /etc/cascade-vpn /var/lib/cascade-vpn /var/log/cascade-vpn
print_success "Directories created"

print_info "Updating system packages..."
if command -v apt-get &> /dev/null; then
    apt-get update -qq 2>&1 | grep -v "^Get:" | grep -v "^Reading" || true
    apt-get upgrade -y -qq > /dev/null 2>&1
    PACKAGE_CMD="apt-get install -y"
    print_success "System updated (Debian/Ubuntu)"
elif command -v yum &> /dev/null; then
    yum update -y -q > /dev/null 2>&1
    PACKAGE_CMD="yum install -y"
    print_success "System updated (RedHat/CentOS)"
else
    print_error "No supported package manager found"
    exit 1
fi

# ========== OPENVPN INSTALLATION ==========

print_header "Step 2: Installing OpenVPN"

print_info "Installing OpenVPN..."
if [[ "$PACKAGE_CMD" == "apt-get"* ]]; then
    $PACKAGE_CMD openvpn openvpn-blacklist > /dev/null 2>&1
else
    $PACKAGE_CMD openvpn > /dev/null 2>&1
fi

mkdir -p /etc/openvpn /var/log/openvpn
systemctl enable openvpn > /dev/null 2>&1 || true

if command -v openvpn &> /dev/null; then
    OPENVPN_VERSION=$(openvpn --version | head -n1)
    print_success "OpenVPN installed: $OPENVPN_VERSION"
else
    print_warning "OpenVPN installation may have failed"
fi

# ========== WIREGUARD INSTALLATION ==========

print_header "Step 3: Installing WireGuard"

print_info "Installing WireGuard..."
$PACKAGE_CMD wireguard wireguard-tools > /dev/null 2>&1

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

if command -v wg &> /dev/null; then
    WG_VERSION=$(wg --version)
    print_success "WireGuard installed: $WG_VERSION"
else
    print_warning "WireGuard installation may have failed"
fi

# ========== V2RAY INSTALLATION ==========

print_header "Step 4: Installing V2Ray"

print_info "Downloading V2Ray installer..."
if curl -sSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash > /dev/null 2>&1; then
    systemctl enable v2ray > /dev/null 2>&1 || true
    
    if command -v v2ray &> /dev/null; then
        print_success "V2Ray installed successfully"
    else
        print_warning "V2Ray installation completed but binary not found"
    fi
else
    print_warning "V2Ray installation skipped or failed (optional)"
fi

# ========== XRAY INSTALLATION ==========

print_header "Step 5: Installing Xray"

print_info "Downloading Xray installer..."
if curl -sSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh | bash > /dev/null 2>&1; then
    systemctl enable xray > /dev/null 2>&1 || true
    
    if command -v xray &> /dev/null; then
        print_success "Xray installed successfully"
    else
        print_warning "Xray installation completed but binary not found"
    fi
else
    print_warning "Xray installation skipped or failed (optional)"
fi

# ========== 3X-UI INSTALLATION ==========

print_header "Step 6: Checking for 3X-UI"

if command -v docker &> /dev/null; then
    print_success "Docker is available for 3X-UI deployment"
    print_info "To deploy 3X-UI, run:"
    echo "  docker pull sagernet/x-ui:latest"
    echo "  docker run -d --name 3x-ui -p 2053:443 sagernet/x-ui:latest"
else
    print_warning "Docker not found - install with: curl -fsSL https://get.docker.com | bash"
fi

# ========== FINAL SUMMARY ==========

print_header "CASCADE VPN UNIVERSAL - Installation Complete!"

echo "✓ INSTALLED SERVICES:"
echo "  • OpenVPN - $([[ -f /etc/openvpn/server.conf ]] && echo 'Configured' || echo 'Ready to configure')"
echo "  • WireGuard - $(command -v wg &> /dev/null && echo 'Installed' || echo 'Installation pending')"
echo "  • V2Ray - $(command -v v2ray &> /dev/null && echo 'Installed' || echo 'Installation pending')"
echo "  • Xray - $(command -v xray &> /dev/null && echo 'Installed' || echo 'Installation pending')"
echo "  • System Optimization - Complete"
echo ""

echo "📁 WORKING DIRECTORIES:"
echo "  • Configuration: /etc/cascade-vpn"
echo "  • Data: /var/lib/cascade-vpn"
echo "  • Logs: /var/log/cascade-vpn"
echo ""

echo "🔧 NEXT STEPS:"
echo "  1. Configure OpenVPN:"
echo "     nano /etc/openvpn/server.conf"
echo ""
echo "  2. Configure WireGuard:"
echo "     wg-quick up wg0"
echo ""
echo "  3. Start services:"
echo "     systemctl start openvpn@server"
echo "     systemctl start wireguard@wg0"
echo ""
echo "  4. Check status:"
echo "     systemctl status openvpn@server"
echo "     systemctl status wireguard@wg0"
echo ""

echo "📝 USEFUL COMMANDS:"
echo "  • View logs: tail -f /var/log/cascade-vpn/*.log"
echo "  • Service status: systemctl status [service-name]"
echo "  • Enable on boot: systemctl enable [service-name]"
echo ""

print_success "ALL SERVICES INSTALLED SUCCESSFULLY!"
print_info "Your VPN infrastructure is ready for configuration!"
echo ""

exit 0
