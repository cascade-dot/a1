#!/bin/bash
# install.sh - Main Cascade VPN Universal Installer
# A comprehensive VPN setup automation with traffic obfuscation

set -euo pipefail

# ==================== CONFIGURATION ====================
MAIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="1.0.0"
readonly INSTALL_DATE=$(date +"%Y-%m-%d %H:%M:%S")

# Source utilities
source "$MAIN_SCRIPT_DIR/utils/colors.sh"
source "$MAIN_SCRIPT_DIR/utils/logger.sh"
source "$MAIN_SCRIPT_DIR/utils/validators.sh"

# ==================== INTERACTIVE MENU ====================

show_menu() {
    print_header "Cascade VPN Universal Installer v$VERSION"
    
    echo "Select VPN service to install:"
    echo ""
    echo "  ${CYAN}[1]${NC} 3X-UI Control Panel (Xray/V2Ray management)"
    echo "  ${CYAN}[2]${NC} WireGuard VPN (with wg-easy web interface)"
    echo "  ${CYAN}[3]${NC} V2Ray Proxy"
    echo "  ${CYAN}[4]${NC} Xray Proxy"
    echo "  ${CYAN}[5]${NC} Complete Setup (All services)"
    echo ""
    echo "Obfuscation modules (optional):"
    echo "  ${CYAN}[6]${NC} Shadowsocks 2022"
    echo "  ${CYAN}[7]${NC} gRPC + TLS Masking"
    echo "  ${CYAN}[8]${NC} Trojan Protocol"
    echo "  ${CYAN}[9]${NC} VLESS WebSocket + TLS"
    echo "  ${CYAN}[10]${NC} UDP2RAW Tunneling"
    echo ""
    echo "System:"
    echo "  ${CYAN}[11]${NC} System Optimization Only"
    echo "  ${CYAN}[12]${NC} SSL Certificate Management"
    echo "  ${CYAN}[0]${NC} Exit"
    echo ""
}

# ==================== INSTALLATION FUNCTIONS ====================

install_3x_ui() {
    log_section_start "Installing 3X-UI Panel"
    
    print_info "3X-UI is a web panel for managing Xray/V2Ray proxies"
    
    if [[ ! -f "$MAIN_SCRIPT_DIR/services/3x-ui/install.sh" ]]; then
        print_error "3X-UI installation script not found"
        return 1
    fi
    
    # Source and run installation
    source "$MAIN_SCRIPT_DIR/services/3x-ui/install.sh"
    
    log_success "3X-UI installation completed"
    log_section_end "Installing 3X-UI Panel" "success"
}

install_wireguard() {
    log_section_start "Installing WireGuard VPN"
    
    print_info "WireGuard with wg-easy web interface for client management"
    
    if [[ ! -f "$MAIN_SCRIPT_DIR/services/wireguard/wg-easy.sh" ]]; then
        print_error "WireGuard installation script not found"
        return 1
    fi
    
    source "$MAIN_SCRIPT_DIR/services/wireguard/wg-easy.sh"
    
    log_success "WireGuard installation completed"
    log_section_end "Installing WireGuard VPN" "success"
}

install_shadowsocks() {
    log_section_start "Installing Shadowsocks 2022"
    
    print_info "Shadowsocks for traffic obfuscation"
    
    if [[ ! -f "$MAIN_SCRIPT_DIR/modules/obfuscation/shadowsocks.sh" ]]; then
        print_error "Shadowsocks installation script not found"
        return 1
    fi
    
    source "$MAIN_SCRIPT_DIR/modules/obfuscation/shadowsocks.sh"
    
    log_success "Shadowsocks installation completed"
    log_section_end "Installing Shadowsocks 2022" "success"
}

install_grpc_tls() {
    log_section_start "Installing gRPC + TLS Masking"
    
    print_info "gRPC protocol with TLS encryption for traffic masking"
    
    if [[ ! -f "$MAIN_SCRIPT_DIR/modules/obfuscation/grpc-tls.sh" ]]; then
        print_error "gRPC+TLS installation script not found"
        return 1
    fi
    
    source "$MAIN_SCRIPT_DIR/modules/obfuscation/grpc-tls.sh"
    
    log_success "gRPC+TLS installation completed"
    log_section_end "Installing gRPC + TLS Masking" "success"
}

setup_certificates() {
    log_section_start "SSL Certificate Setup"
    
    echo ""
    print_subheader "Certificate Management"
    echo "  ${CYAN}[1]${NC} Let's Encrypt (Automated)"
    echo "  ${CYAN}[2]${NC} Self-Signed Certificate"
    echo "  ${CYAN}[0]${NC} Skip"
    echo ""
    read -p "Choose option: " cert_choice
    
    case $cert_choice in
        1)
            if [[ ! -f "$MAIN_SCRIPT_DIR/modules/certificates/letsencrypt.sh" ]]; then
                print_error "Let's Encrypt script not found"
                return 1
            fi
            source "$MAIN_SCRIPT_DIR/modules/certificates/letsencrypt.sh"
            install_certbot
            ;;
        2)
            if [[ ! -f "$MAIN_SCRIPT_DIR/modules/certificates/selfsigned.sh" ]]; then
                print_error "Self-signed script not found"
                return 1
            fi
            source "$MAIN_SCRIPT_DIR/modules/certificates/selfsigned.sh"
            ;;
        0)
            print_info "Certificate setup skipped"
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
    
    log_section_end "SSL Certificate Setup" "success"
}

system_optimization_only() {
    log_section_start "System Optimization"
    
    print_info "Optimizing system for VPN services"
    
    if [[ ! -f "$MAIN_SCRIPT_DIR/core/system-optimization.sh" ]]; then
        print_error "System optimization script not found"
        return 1
    fi
    
    source "$MAIN_SCRIPT_DIR/core/system-optimization.sh"
    main
    
    log_section_end "System Optimization" "success"
}

# ==================== MAIN INSTALLATION FLOW ====================

main() {
    # Initialize logging
    init_logging
    
    log_info "Cascade VPN Installation Started"
    print_header "CASCADE VPN UNIVERSAL - Installation"
    
    # Check prerequisites
    print_info "Checking prerequisites..."
    if [[ ! -f "$MAIN_SCRIPT_DIR/core/prerequisites.sh" ]]; then
        print_error "Prerequisites script not found"
        return 1
    fi
    
    source "$MAIN_SCRIPT_DIR/core/prerequisites.sh"
    
    if ! setup_prerequisites; then
        print_error "Prerequisites check failed"
        return 1
    fi
    
    if ! create_working_directories; then
        print_error "Failed to create working directories"
        return 1
    fi
    
    if ! setup_environment_variables; then
        print_error "Failed to setup environment"
        return 1
    fi
    
    # Interactive menu
    while true; do
        show_menu
        read -p "Enter your choice [0-12]: " choice
        
        case $choice in
            1)
                install_3x_ui
                ;;
            2)
                install_wireguard
                ;;
            3)
                print_warning "V2Ray installation not yet implemented"
                ;;
            4)
                print_warning "Xray installation not yet implemented"
                ;;
            5)
                print_info "Installing complete setup..."
                install_3x_ui
                install_wireguard
                setup_certificates
                system_optimization_only
                ;;
            6)
                install_shadowsocks
                ;;
            7)
                install_grpc_tls
                ;;
            8)
                print_warning "Trojan installation not yet implemented"
                ;;
            9)
                print_warning "VLESS WebSocket+TLS installation not yet implemented"
                ;;
            10)
                print_warning "UDP2RAW installation not yet implemented"
                ;;
            11)
                system_optimization_only
                ;;
            12)
                setup_certificates
                ;;
            0)
                print_info "Installation cancelled"
                return 0
                ;;
            *)
                print_error "Invalid choice. Please try again."
                ;;
        esac
        
        print_separator
        read -p "Install another component? [y/N]: " another
        if [[ "$another" != "y" && "$another" != "Y" ]]; then
            break
        fi
    done
    
    # Final summary
    print_header "Installation Complete"
    log_success "Cascade VPN installation finished"
    
    print_info "Next steps:"
    print_value "Configuration" "/etc/cascade-vpn"
    print_value "Logs" "/var/log/cascade-vpn"
    print_value "Data" "/var/lib/cascade-vpn"
    echo ""
    print_info "To start services:"
    echo "  sudo systemctl start cascade-vpn"
    echo "  sudo systemctl status cascade-vpn"
    echo ""
    
    # Export logs
    log_info "Installation logs exported"
}

# ==================== ENTRY POINT ====================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    echo "Usage: sudo bash install.sh"
    exit 1
fi

# Run main installation
main "$@"
exit $?
