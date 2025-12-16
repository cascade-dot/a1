#!/bin/bash
# CASCADE VPN UNIVERSAL - Two-Mode Installer
# Mode 1: LOCAL - Configure port forwarding on this machine
# Mode 2: REMOTE - Install VPN server on remote machine

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

# ==================== MAIN MENU ====================

print_header "CASCADE VPN UNIVERSAL v$VERSION"

echo "Select operation mode:"
echo ""
echo -e "  ${CYAN}[1]${NC} LOCAL MODE - Configure port forwarding/proxying on THIS machine"
echo -e "  ${CYAN}[2]${NC} REMOTE MODE - Install VPN server on REMOTE machine"
echo -e "  ${CYAN}[0]${NC} Exit"
echo ""
read -p "Select mode [0-2]: " MODE_CHOICE

case $MODE_CHOICE in
    0)
        print_info "Exiting..."
        exit 0
        ;;
    1)
        # LOCAL MODE - Port forwarding configuration
        print_header "CASCADE VPN - LOCAL MODE (Port Forwarding/Proxying)"
        
        echo "Configure port forwarding and proxying options:"
        echo ""
        echo -e "  ${CYAN}[1]${NC} Setup iptables port forwarding"
        echo -e "  ${CYAN}[2]${NC} Setup nftables port forwarding"
        echo -e "  ${CYAN}[3]${NC} Configure Nginx reverse proxy"
        echo -e "  ${CYAN}[4]${NC} Configure HAProxy load balancer"
        echo -e "  ${CYAN}[5]${NC} Setup Shadowsocks client"
        echo -e "  ${CYAN}[6]${NC} Setup V2Ray client"
        echo -e "  ${CYAN}[7]${NC} All port forwarding options"
        echo -e "  ${CYAN}[0]${NC} Back"
        echo ""
        read -p "Select option [0-7]: " LOCAL_CHOICE
        
        case $LOCAL_CHOICE in
            0)
                exit 0
                ;;
            1)
                print_header "Setting up iptables port forwarding"
                print_info "Enter source port (on this machine):"
                read SOURCE_PORT
                print_info "Enter destination IP (remote VPN server):"
                read DEST_IP
                print_info "Enter destination port (on remote server):"
                read DEST_PORT
                
                sudo bash << EOF
                # Enable IP forwarding
                sysctl -w net.ipv4.ip_forward=1
                echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
                
                # Add iptables rule
                iptables -t nat -A PREROUTING -p tcp --dport $SOURCE_PORT -j DNAT --to-destination $DEST_IP:$DEST_PORT
                iptables -t nat -A POSTROUTING -j MASQUERADE
                
                # Save rules
                iptables-save > /etc/iptables.rules
EOF
                
                print_success "Port forwarding configured: $SOURCE_PORT -> $DEST_IP:$DEST_PORT"
                ;;
            2)
                print_header "Setting up nftables port forwarding"
                print_info "Enter source port:"
                read SOURCE_PORT
                print_info "Enter destination IP:"
                read DEST_IP
                print_info "Enter destination port:"
                read DEST_PORT
                
                sudo bash << EOF
                nft add rule ip nat prerouting tcp dport $SOURCE_PORT dnat to $DEST_IP:$DEST_PORT
                nft add rule ip nat postrouting masquerade
EOF
                
                print_success "NFTables port forwarding configured"
                ;;
            3)
                print_header "Setting up Nginx reverse proxy"
                print_info "Installing Nginx..."
                sudo apt-get update -qq > /dev/null 2>&1
                sudo apt-get install -y nginx > /dev/null 2>&1
                print_success "Nginx installed"
                
                print_info "Enter remote VPN server IP:"
                read REMOTE_IP
                print_info "Enter remote server port:"
                read REMOTE_PORT
                
                sudo bash << EOF
                cat > /etc/nginx/sites-available/cascade-vpn << 'NGINX'
upstream cascade_backend {
    server $REMOTE_IP:$REMOTE_PORT;
}

server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://cascade_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX
                
                ln -sf /etc/nginx/sites-available/cascade-vpn /etc/nginx/sites-enabled/
                systemctl restart nginx
EOF
                
                print_success "Nginx reverse proxy configured for $REMOTE_IP:$REMOTE_PORT"
                ;;
            4)
                print_header "Setting up HAProxy load balancer"
                print_info "Installing HAProxy..."
                sudo apt-get update -qq > /dev/null 2>&1
                sudo apt-get install -y haproxy > /dev/null 2>&1
                print_success "HAProxy installed"
                print_info "Configure HAProxy manually at: /etc/haproxy/haproxy.cfg"
                ;;
            5)
                print_header "Setting up Shadowsocks client"
                print_info "Installing Shadowsocks..."
                sudo apt-get update -qq > /dev/null 2>&1
                sudo apt-get install -y shadowsocks-libev > /dev/null 2>&1
                print_success "Shadowsocks installed"
                print_info "Configure at: /etc/shadowsocks-libev/config.json"
                ;;
            6)
                print_header "Setting up V2Ray client"
                print_info "Installing V2Ray..."
                if timeout 300 bash -c 'curl -sSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash' > /dev/null 2>&1; then
                    print_success "V2Ray installed"
                    print_info "Configure at: /etc/v2ray/config.json"
                else
                    print_error "V2Ray installation failed"
                fi
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        ;;
        
    2)
        # REMOTE MODE - VPN Server installation
        print_header "CASCADE VPN - REMOTE MODE (VPN Server Installation)"
        
        echo "Select VPN server to install on remote machine:"
        echo ""
        echo -e "  ${CYAN}[1]${NC} OpenVPN"
        echo -e "  ${CYAN}[2]${NC} WireGuard"
        echo -e "  ${CYAN}[3]${NC} V2Ray"
        echo -e "  ${CYAN}[4]${NC} Xray"
        echo -e "  ${CYAN}[5]${NC} All Services (OpenVPN + WireGuard + V2Ray + Xray)"
        echo -e "  ${CYAN}[0]${NC} Back"
        echo ""
        read -p "Select service [0-5]: " REMOTE_CHOICE
        
        case $REMOTE_CHOICE in
            0)
                exit 0
                ;;
            1|2|3|4|5)
                print_header "Remote VPN Server Installation"
                
                print_info "Enter remote server IP address:"
                read REMOTE_SERVER
                
                print_info "Enter SSH port (default 22):"
                read -p "[22]: " SSH_PORT
                SSH_PORT=${SSH_PORT:-22}
                
                print_info "Generating installation command for remote server..."
                echo ""
                echo "Run this command on your remote server:"
                echo ""
                echo "curl -sSL https://raw.githubusercontent.com/cascade-dot/a1/main/auto-install.sh | sudo bash -s $REMOTE_CHOICE"
                echo ""
                echo "Or use SSH to run remotely:"
                echo "ssh -p $SSH_PORT root@$REMOTE_SERVER 'curl -sSL https://raw.githubusercontent.com/cascade-dot/a1/main/auto-install.sh | sudo bash -s $REMOTE_CHOICE'"
                echo ""
                print_success "Installation command ready!"
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        ;;
        
    *)
        print_error "Invalid mode!"
        exit 1
        ;;
esac

echo ""
print_success "Operation completed!"
echo ""

exit 0
