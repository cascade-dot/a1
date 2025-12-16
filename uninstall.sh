#!/bin/bash
# uninstall.sh - Remove Cascade VPN Components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/utils/colors.sh"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/utils/validators.sh"

# ==================== UNINSTALL FUNCTIONS ====================

remove_3x_ui() {
    log_section_start "Removing 3X-UI Panel"
    
    print_info "Stopping 3X-UI service..."
    systemctl stop 3x-ui 2>/dev/null || true
    systemctl disable 3x-ui 2>/dev/null || true
    
    print_info "Removing Docker containers..."
    docker-compose -f /opt/3x-ui/docker-compose.yml down 2>/dev/null || true
    
    print_info "Removing installation directory..."
    rm -rf /opt/3x-ui
    rm -rf /etc/3x-ui
    rm -f /etc/systemd/system/3x-ui.service
    
    systemctl daemon-reload
    log_success "3X-UI removed"
    log_section_end "Removing 3X-UI Panel" "success"
}

remove_wireguard() {
    log_section_start "Removing WireGuard"
    
    print_info "Stopping WireGuard service..."
    systemctl stop wg-easy 2>/dev/null || true
    systemctl disable wg-easy 2>/dev/null || true
    
    print_info "Removing Docker containers..."
    docker-compose -f /opt/wg-easy/docker-compose.yml down 2>/dev/null || true
    
    print_info "Removing installation directory..."
    rm -rf /opt/wg-easy
    rm -f /etc/systemd/system/wg-easy.service
    
    # Remove WireGuard configuration
    rm -rf /etc/wireguard/cascade-vpn 2>/dev/null || true
    
    systemctl daemon-reload
    log_success "WireGuard removed"
    log_section_end "Removing WireGuard" "success"
}

remove_shadowsocks() {
    log_section_start "Removing Shadowsocks"
    
    print_info "Stopping Shadowsocks service..."
    systemctl stop shadowsocks 2>/dev/null || true
    systemctl disable shadowsocks 2>/dev/null || true
    
    print_info "Removing binaries..."
    rm -f /usr/local/bin/ssserver
    rm -f /usr/local/bin/sslocal
    rm -f /usr/local/bin/ssmanager
    rm -f /usr/local/bin/ssurl
    
    print_info "Removing configuration..."
    rm -rf /etc/shadowsocks
    rm -f /etc/systemd/system/shadowsocks.service
    
    systemctl daemon-reload
    log_success "Shadowsocks removed"
    log_section_end "Removing Shadowsocks" "success"
}

remove_grpc_tls() {
    log_section_start "Removing gRPC+TLS"
    
    print_info "Stopping gRPC service..."
    systemctl stop xray-grpc 2>/dev/null || true
    systemctl disable xray-grpc 2>/dev/null || true
    
    print_info "Removing configuration..."
    rm -rf /etc/xray-grpc
    rm -f /etc/systemd/system/xray-grpc.service
    
    systemctl daemon-reload
    log_success "gRPC+TLS removed"
    log_section_end "Removing gRPC+TLS" "success"
}

remove_cascade_vpn_core() {
    log_section_start "Removing Cascade VPN Core"
    
    print_info "Stopping Cascade VPN service..."
    systemctl stop cascade-vpn 2>/dev/null || true
    systemctl disable cascade-vpn 2>/dev/null || true
    
    print_info "Removing core files..."
    rm -rf /opt/cascade-vpn
    rm -f /etc/systemd/system/cascade-vpn.service
    
    systemctl daemon-reload
    log_success "Cascade VPN core removed"
    log_section_end "Removing Cascade VPN Core" "success"
}

remove_all() {
    print_header "REMOVING ALL CASCADE VPN COMPONENTS"
    print_warning "This will remove all VPN services and configurations"
    read -p "Are you sure? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Removal cancelled"
        return 0
    fi
    
    remove_3x_ui || true
    remove_wireguard || true
    remove_shadowsocks || true
    remove_grpc_tls || true
    remove_cascade_vpn_core || true
    
    # Remove system configurations
    print_info "Removing system configurations..."
    rm -f /etc/sysctl.d/99-cascade-vpn.conf
    rm -f /etc/security/limits.d/99-cascade-vpn.conf
    rm -f /etc/nginx/sites-available/cascade-vpn
    rm -f /etc/nginx/sites-enabled/cascade-vpn
    sysctl -p > /dev/null 2>&1 || true
    
    # Remove log directories (backup first)
    print_info "Backing up logs before removal..."
    tar -czf "$HOME/cascade-vpn-logs-$(date +%s).tar.gz" /var/log/cascade-vpn 2>/dev/null || true
    rm -rf /var/log/cascade-vpn
    rm -rf /var/lib/cascade-vpn
    rm -rf /etc/cascade-vpn
    
    print_header "All Components Removed Successfully"
}

show_menu() {
    print_header "Cascade VPN - Uninstall"
    
    echo "Select component to remove:"
    echo ""
    echo "  ${CYAN}[1]${NC} 3X-UI Panel"
    echo "  ${CYAN}[2]${NC} WireGuard VPN"
    echo "  ${CYAN}[3]${NC} Shadowsocks"
    echo "  ${CYAN}[4]${NC} gRPC+TLS"
    echo "  ${CYAN}[5]${NC} Remove All Components"
    echo "  ${CYAN}[0]${NC} Exit"
    echo ""
}

# ==================== MAIN ====================

main() {
    init_logging
    
    log_info "Cascade VPN Uninstall Started"
    
    check_root
    
    while true; do
        show_menu
        read -p "Enter your choice [0-5]: " choice
        
        case $choice in
            1)
                remove_3x_ui
                ;;
            2)
                remove_wireguard
                ;;
            3)
                remove_shadowsocks
                ;;
            4)
                remove_grpc_tls
                ;;
            5)
                remove_all
                break
                ;;
            0)
                print_info "Uninstall cancelled"
                return 0
                ;;
            *)
                print_error "Invalid choice"
                ;;
        esac
        
        print_separator
        read -p "Remove another component? [y/N]: " another
        if [[ "$another" != "y" && "$another" != "Y" ]]; then
            break
        fi
    done
    
    print_info "Uninstall completed"
}

# Entry point
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

main "$@"
exit $?
