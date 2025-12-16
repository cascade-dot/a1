#!/bin/bash
# services/openvpn/install.sh - OpenVPN server installation and configuration

set -euo pipefail

OVPN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$OVPN_SCRIPT_DIR/../../utils/colors.sh"
source "$OVPN_SCRIPT_DIR/../../utils/logger.sh"

# Configuration
readonly OPENVPN_DIR="/etc/openvpn"
readonly OPENVPN_CONFIG="$OPENVPN_DIR/server.conf"
readonly PKI_DIR="$OPENVPN_DIR/easy-rsa/pki"
readonly CLIENTS_DIR="/var/cascade-vpn/openvpn-clients"
readonly DEFAULT_PORT=1194
readonly DEFAULT_PROTO="udp"
readonly DEFAULT_CIPHER="AES-256-GCM"

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

install_openvpn() {
    print_header "Installing OpenVPN Server"
    
    # Update package manager
    print_info "Updating package manager..."
    apt-get update -qq
    
    # Install OpenVPN and EasyRSA
    print_info "Installing OpenVPN and EasyRSA..."
    apt-get install -y openvpn easy-rsa > /dev/null 2>&1 || {
        print_error "Failed to install OpenVPN packages"
        return 1
    }
    
    print_success "OpenVPN installed successfully"
}

setup_pki() {
    print_info "Setting up PKI (Public Key Infrastructure)..."
    
    # Initialize EasyRSA
    mkdir -p "$OPENVPN_DIR/easy-rsa"
    cd "$OPENVPN_DIR/easy-rsa"
    
    # Copy EasyRSA template if not exists
    if [ ! -f ./easyrsa ]; then
        cp /usr/share/easy-rsa/* . 2>/dev/null || {
            # Fallback: build from source
            git clone https://github.com/OpenVPN/easy-rsa.git . 2>/dev/null || true
        }
    fi
    
    # Initialize PKI
    if [ ! -d "$PKI_DIR" ]; then
        print_info "Initializing PKI directory..."
        ./easyrsa init-pki nopass > /dev/null 2>&1 || true
    fi
    
    # Build CA (Certificate Authority)
    if [ ! -f "$PKI_DIR/ca.crt" ]; then
        print_info "Building CA certificate (this may take a moment)..."
        echo -e "\n\nCascade VPN" | ./easyrsa build-ca nopass > /dev/null 2>&1 || {
            print_error "Failed to build CA certificate"
            return 1
        }
    fi
    
    # Generate server certificate and key
    if [ ! -f "$PKI_DIR/issued/server.crt" ]; then
        print_info "Generating server certificate..."
        ./easyrsa gen-req server nopass > /dev/null 2>&1
        ./easyrsa sign-req server server nopass > /dev/null 2>&1 || {
            print_error "Failed to generate server certificate"
            return 1
        }
    fi
    
    # Generate Diffie-Hellman parameters
    if [ ! -f "$PKI_DIR/dh.pem" ]; then
        print_info "Generating Diffie-Hellman parameters (this may take several minutes)..."
        openssl dhparam -out "$PKI_DIR/dh.pem" 2048 > /dev/null 2>&1 || {
            print_error "Failed to generate DH parameters"
            return 1
        }
    fi
    
    # Generate TLS auth key
    if [ ! -f "$OPENVPN_DIR/ta.key" ]; then
        print_info "Generating TLS authentication key..."
        openvpn --genkey secret "$OPENVPN_DIR/ta.key" || {
            print_error "Failed to generate TLS auth key"
            return 1
        }
    fi
    
    chown -R root:root "$OPENVPN_DIR/easy-rsa"
    chmod 700 "$OPENVPN_DIR/easy-rsa/pki"
    
    print_success "PKI setup completed"
}

generate_server_config() {
    local port=$1
    local proto=$2
    local cipher=$3
    
    print_info "Generating server configuration..."
    
    cat > "$OPENVPN_CONFIG" <<EOF
# OpenVPN Server Configuration
port $port
proto $proto
dev tun

ca $PKI_DIR/ca.crt
cert $PKI_DIR/issued/server.crt
key $PKI_DIR/private/server.key
dh $PKI_DIR/dh.pem
tls-auth $OPENVPN_DIR/ta.key 0

cipher $cipher
ncp-ciphers "$cipher:AES-128-GCM:CHACHA20-POLY1305"

topology subnet
server 10.8.0.0 255.255.255.0

# DNS settings
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
push "redirect-gateway def1 bypass-dhcp"

# Keep connection alive
keepalive 10 120

# Compression
compress lz4-v2
push "compress lz4-v2"

# Security
user nobody
group nogroup
persist-key
persist-tun

# Logging
log /var/log/openvpn/server.log
verb 3
mute 20

# CRL (Certificate Revocation List)
crl-verify $PKI_DIR/crl.pem
EOF

    # Create CRL (empty initially)
    if [ ! -f "$PKI_DIR/crl.pem" ]; then
        openssl ca -gencrl -out "$PKI_DIR/crl.pem" -keyfile "$PKI_DIR/private/ca.key" -cert "$PKI_DIR/ca.crt" > /dev/null 2>&1 || true
    fi
    
    chmod 600 "$OPENVPN_CONFIG"
    print_success "Server configuration created"
}

enable_ip_forwarding() {
    print_info "Enabling IP forwarding..."
    
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Make it persistent
    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        sysctl -p > /dev/null 2>&1
    fi
    
    print_success "IP forwarding enabled"
}

setup_firewall() {
    print_info "Configuring firewall rules..."
    
    # Get default interface
    local default_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [ -z "$default_interface" ]; then
        print_warning "Could not determine default interface, skipping firewall rules"
        return 0
    fi
    
    # Apply masquerading for VPN clients
    if command -v ufw &> /dev/null && ufw status | grep -q active; then
        # UFW is active
        ufw allow 1194/udp > /dev/null 2>&1
        ufw allow 1194/tcp > /dev/null 2>&1
    elif command -v firewall-cmd &> /dev/null; then
        # firewalld is active
        firewall-cmd --permanent --add-port=1194/udp > /dev/null 2>&1
        firewall-cmd --permanent --add-port=1194/tcp > /dev/null 2>&1
        firewall-cmd --permanent --add-masquerade > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
    fi
    
    # Apply iptables rules
    if iptables -t nat -L POSTROUTING -n | grep -q "all -- 10.8.0.0"; then
        # Already configured
        return 0
    fi
    
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$default_interface" -j MASQUERADE
    
    # Save iptables rules (if iptables-persistent is installed)
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    print_success "Firewall rules configured"
}

start_openvpn() {
    print_info "Starting OpenVPN service..."
    
    # Create log directory
    mkdir -p /var/log/openvpn
    chown -R nobody:nogroup /var/log/openvpn
    
    # Enable and start service
    systemctl enable openvpn@server > /dev/null 2>&1
    systemctl start openvpn@server || {
        print_error "Failed to start OpenVPN service"
        print_info "Checking logs: journalctl -u openvpn@server -n 20"
        return 1
    }
    
    sleep 2
    
    # Check if service is running
    if systemctl is-active --quiet openvpn@server; then
        print_success "OpenVPN service started successfully"
        return 0
    else
        print_error "OpenVPN service failed to start"
        return 1
    fi
}

install_openvpn_ui() {
    print_info "Installing OpenVPN Web Management Panel..."
    
    # Install Python dependencies
    print_info "Installing Python dependencies..."
    apt-get install -y python3 python3-pip python3-venv > /dev/null 2>&1 || {
        print_warning "Failed to install Python, skipping UI"
        return 1
    }
    
    # Install Flask and dependencies
    pip3 install flask qrcode pillow pyopenssl > /dev/null 2>&1 || {
        print_warning "Failed to install Python packages, skipping UI"
        return 1
    }
    
    # Copy UI files
    local ui_dir="/opt/openvpn-ui"
    mkdir -p "$ui_dir/templates"
    
    # Copy main script
    cp "$OVPN_SCRIPT_DIR/openvpn-ui.py" "$ui_dir/" || return 1
    
    # Copy templates
    cp "$OVPN_SCRIPT_DIR/templates/login.html" "$ui_dir/templates/" || return 1
    cp "$OVPN_SCRIPT_DIR/templates/dashboard.html" "$ui_dir/templates/" || return 1
    cp "$OVPN_SCRIPT_DIR/templates/settings.html" "$ui_dir/templates/" || return 1
    
    chmod +x "$ui_dir/openvpn-ui.py"
    
    # Create systemd service
    cat > /etc/systemd/system/openvpn-ui.service <<EOF
[Unit]
Description=OpenVPN Web Management Panel
Documentation=https://github.com/adminbk/cascade-vpn-universal
After=network-online.target openvpn@server.service
Wants=network-online.target openvpn@server.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$ui_dir
ExecStart=/usr/bin/python3 $ui_dir/openvpn-ui.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable openvpn-ui > /dev/null 2>&1
    systemctl start openvpn-ui || {
        print_warning "Failed to start OpenVPN UI service"
        return 1
    }
    
    sleep 2
    
    if systemctl is-active --quiet openvpn-ui; then
        print_success "OpenVPN UI installed and started"
        
        # Save setup info
        local setup_log="/var/log/openvpn/ui-setup.log"
        {
            echo "OpenVPN Web Panel Setup Log"
            echo "============================="
            echo "Installation Date: $(date)"
            echo "URL: https://\$(hostname -I | awk '{print \$1}'):8443"
            echo "Default User: admin"
            echo "Password: Check server console output during installation"
            echo ""
            echo "Web Panel Location: $ui_dir"
            echo "Service: openvpn-ui"
            echo "View logs: journalctl -u openvpn-ui -f"
        } > "$setup_log"
        
        return 0
    else
        print_warning "OpenVPN UI failed to start"
        return 1
    fi
}

# ============================================================================
# CLIENT CONFIGURATION GENERATION
# ============================================================================

generate_client_keys() {
    local client_name=$1
    
    print_info "Generating keys for client: $client_name"
    
    cd "$OPENVPN_DIR/easy-rsa"
    
    # Generate client certificate
    if [ ! -f "$PKI_DIR/issued/${client_name}.crt" ]; then
        ./easyrsa gen-req "$client_name" nopass > /dev/null 2>&1
        ./easyrsa sign-req client "$client_name" nopass > /dev/null 2>&1 || {
            print_error "Failed to generate client certificate"
            return 1
        }
    fi
    
    print_success "Client keys generated: $client_name"
}

generate_client_config() {
    local client_name=$1
    local server_ip=${2:-$(curl -s ifconfig.me)}
    local server_port=${3:-1194}
    local proto=${4:-udp}
    
    print_info "Generating client configuration for: $client_name"
    
    mkdir -p "$CLIENTS_DIR"
    
    local config_file="$CLIENTS_DIR/${client_name}.ovpn"
    
    cat > "$config_file" <<EOF
client
dev tun
proto $proto
remote $server_ip $server_port

resolv-retry infinite
nobind

# TLS settings
remote-cert-tls server
tls-auth [inline] 1

# Encryption
cipher AES-256-GCM
ncp-ciphers "AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305"

# DNS
setenv opt block-outside-dns
dhcp-option DNS 1.1.1.1
dhcp-option DNS 8.8.8.8

# Compression
compress lz4-v2

# Security
user nobody
group nogroup

persist-key
persist-tun

verb 3
mute 20

<ca>
$(cat "$PKI_DIR/ca.crt")
</ca>

<cert>
$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$PKI_DIR/issued/${client_name}.crt")
</cert>

<key>
$(cat "$PKI_DIR/private/${client_name}.key")
</key>

<tls-auth>
$(cat "$OPENVPN_DIR/ta.key")
</tls-auth>

EOF

    chmod 600 "$config_file"
    
    print_success "Client config created: $config_file"
}

# ============================================================================
# MAIN INSTALLATION FLOW
# ============================================================================

main() {
    print_header "OpenVPN Installation"
    
    # Check if already installed
    if systemctl is-active --quiet openvpn@server; then
        print_warning "OpenVPN appears to be already installed and running"
        print_info "Config location: $OPENVPN_CONFIG"
        print_info "Clients location: $CLIENTS_DIR"
        return 0
    fi
    
    # Installation steps
    install_openvpn || return 1
    setup_pki || return 1
    generate_server_config "$DEFAULT_PORT" "$DEFAULT_PROTO" "$DEFAULT_CIPHER" || return 1
    enable_ip_forwarding || return 1
    setup_firewall || return 1
    start_openvpn || return 1
    
    # Generate initial client config
    print_info "Generating initial client configuration..."
    generate_client_keys "client1" || true
    generate_client_config "client1" || true
    
    # Install web management panel
    print_info "Installing OpenVPN Management Panel..."
    install_openvpn_ui || print_warning "Web panel installation skipped (optional)"
    
    print_header "OpenVPN Installation Complete!"
    echo ""
    echo "📋 Configuration Paths:"
    echo "   Server config: $OPENVPN_CONFIG"
    echo "   Clients dir: $CLIENTS_DIR"
    echo "   CA cert: $PKI_DIR/ca.crt"
    echo ""
    echo "🌐 Web Management Panel:"
    echo "   URL: https://server-ip:8443"
    echo "   Default user: admin"
    echo "   Password: Check /var/log/openvpn/ui-setup.log"
    echo ""
    echo "🔑 To generate more clients:"
    echo "   cd $OPENVPN_DIR/easy-rsa"
    echo "   ./easyrsa gen-req CLIENT_NAME nopass"
    echo "   ./easyrsa sign-req client CLIENT_NAME nopass"
    echo ""
    echo "📥 To create client config file:"
    echo "   Use the generate_client_config function or:"
    echo "   cat $CLIENTS_DIR/client1.ovpn"
    echo ""
    echo "✅ OpenVPN is ready to use!"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
