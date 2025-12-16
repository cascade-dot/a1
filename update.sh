#!/bin/bash
# update.sh - Update Cascade VPN Components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/utils/colors.sh"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/utils/validators.sh"

readonly REMOTE_REPO="https://github.com/yourusername/cascade-vpn-universal"
readonly BACKUP_DIR="/var/backups/cascade-vpn"

# ==================== UPDATE FUNCTIONS ====================

backup_current_state() {
    log_section_start "Creating Backup"
    
    print_info "Backing up current configuration..."
    
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/cascade-vpn-backup-$timestamp.tar.gz"
    
    tar -czf "$backup_file" \
        /etc/cascade-vpn \
        /var/lib/cascade-vpn \
        /opt/cascade-vpn \
        /opt/3x-ui \
        /opt/wg-easy \
        /etc/3x-ui \
        /etc/shadowsocks \
        /etc/xray-grpc \
        2>/dev/null || true
    
    print_success "Backup created: $backup_file"
    log_section_end "Creating Backup" "success"
}

update_3x_ui() {
    log_section_start "Updating 3X-UI"
    
    if [[ ! -d /opt/3x-ui ]]; then
        print_warning "3X-UI not installed, skipping"
        return 0
    fi
    
    print_info "Pulling latest Docker image..."
    docker pull sagernet/x-ui:latest > /dev/null
    
    print_info "Restarting 3X-UI service..."
    systemctl restart 3x-ui
    
    print_success "3X-UI updated"
    log_section_end "Updating 3X-UI" "success"
}

update_wireguard() {
    log_section_start "Updating WireGuard"
    
    if [[ ! -d /opt/wg-easy ]]; then
        print_warning "WireGuard not installed, skipping"
        return 0
    fi
    
    print_info "Pulling latest WireGuard image..."
    docker pull weejewel/wg-easy:latest > /dev/null
    
    print_info "Restarting WireGuard service..."
    systemctl restart wg-easy
    
    print_success "WireGuard updated"
    log_section_end "Updating WireGuard" "success"
}

update_shadowsocks() {
    log_section_start "Updating Shadowsocks"
    
    if [[ ! -f /usr/local/bin/ssserver ]]; then
        print_warning "Shadowsocks not installed, skipping"
        return 0
    fi
    
    print_info "Checking for Shadowsocks updates..."
    
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="x86_64" ;;
        aarch64) ARCH="aarch64" ;;
        *) ARCH="x86_64" ;;
    esac
    
    local version=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep tag_name | cut -d'"' -f4)
    print_info "Latest version: $version"
    
    local url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/shadowsocks-${version}.${arch}-unknown-linux-musl.tar.xz"
    
    print_info "Downloading and installing..."
    wget -O /tmp/ss-rust.tar.xz "$url" > /dev/null 2>&1
    tar -xf /tmp/ss-rust.tar.xz -C /tmp/
    
    systemctl stop shadowsocks 2>/dev/null || true
    cp /tmp/ssserver /usr/local/bin/
    chmod +x /usr/local/bin/ssserver
    systemctl start shadowsocks 2>/dev/null || true
    
    print_success "Shadowsocks updated to $version"
    log_section_end "Updating Shadowsocks" "success"
}

update_system() {
    log_section_start "Updating System Packages"
    
    print_info "Updating package repositories..."
    
    if command_exists apt-get; then
        apt-get update -qq
        apt-get upgrade -y -qq > /dev/null
        print_success "Debian/Ubuntu packages updated"
    elif command_exists yum; then
        yum update -y -q > /dev/null
        print_success "RedHat/CentOS packages updated"
    fi
    
    log_section_end "Updating System Packages" "success"
}

update_cascade_vpn_config() {
    log_section_start "Updating Cascade VPN Configuration"
    
    print_info "Applying sysctl optimizations..."
    
    if [[ -f "$SCRIPT_DIR/configs/sysctl/cascade-vpn.conf" ]]; then
        cp "$SCRIPT_DIR/configs/sysctl/cascade-vpn.conf" /etc/sysctl.d/99-cascade-vpn.conf
        sysctl -p /etc/sysctl.d/99-cascade-vpn.conf > /dev/null
        print_success "System configuration updated"
    fi
    
    print_info "Updating Nginx configuration..."
    if [[ -f "$SCRIPT_DIR/configs/nginx/reverse-proxy.conf" ]]; then
        cp "$SCRIPT_DIR/configs/nginx/reverse-proxy.conf" /etc/nginx/sites-available/cascade-vpn 2>/dev/null || true
        nginx -t > /dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true
        print_success "Nginx configuration updated"
    fi
    
    log_section_end "Updating Cascade VPN Configuration" "success"
}

check_version() {
    log_section_start "Version Check"
    
    print_info "Current version: $VERSION"
    
    if command_exists git && [[ -d "$SCRIPT_DIR/.git" ]]; then
        local latest_tag=$(git -C "$SCRIPT_DIR" describe --tags 2>/dev/null || echo "unknown")
        print_info "Latest available: $latest_tag"
    fi
    
    log_section_end "Version Check" "success"
}

show_menu() {
    print_header "Cascade VPN - Update Manager"
    
    echo "Select update option:"
    echo ""
    echo "  ${CYAN}[1]${NC} Update 3X-UI"
    echo "  ${CYAN}[2]${NC} Update WireGuard"
    echo "  ${CYAN}[3]${NC} Update Shadowsocks"
    echo "  ${CYAN}[4]${NC} Update System Packages"
    echo "  ${CYAN}[5]${NC} Update Cascade VPN Configuration"
    echo "  ${CYAN}[6]${NC} Update All Components"
    echo "  ${CYAN}[7]${NC} Check Version"
    echo "  ${CYAN}[0]${NC} Exit"
    echo ""
}

# ==================== MAIN ====================

main() {
    init_logging
    
    log_info "Cascade VPN Update Started"
    
    print_header "CASCADE VPN UPDATE MANAGER"
    
    check_root
    
    # Always backup before updating
    backup_current_state
    
    while true; do
        show_menu
        read -p "Enter your choice [0-7]: " choice
        
        case $choice in
            1)
                update_3x_ui
                ;;
            2)
                update_wireguard
                ;;
            3)
                update_shadowsocks
                ;;
            4)
                update_system
                ;;
            5)
                update_cascade_vpn_config
                ;;
            6)
                print_info "Updating all components..."
                update_system
                update_3x_ui || true
                update_wireguard || true
                update_shadowsocks || true
                update_cascade_vpn_config
                print_success "All updates completed"
                ;;
            7)
                check_version
                ;;
            0)
                print_info "Update manager closed"
                return 0
                ;;
            *)
                print_error "Invalid choice"
                ;;
        esac
        
        print_separator
        read -p "Continue? [y/N]: " another
        if [[ "$another" != "y" && "$another" != "Y" ]]; then
            break
        fi
    done
    
    print_info "Update process completed"
}

# Entry point
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

main "$@"
exit $?
