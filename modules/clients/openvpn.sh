#!/bin/bash
# modules/clients/openvpn.sh - OpenVPN client configuration management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Configuration
readonly OPENVPN_DIR="/etc/openvpn"
readonly OPENVPN_CONFIG="$OPENVPN_DIR/server.conf"
readonly PKI_DIR="$OPENVPN_DIR/easy-rsa/pki"
readonly CLIENTS_DIR="/var/cascade-vpn/openvpn-clients"

# ============================================================================
# CLIENT MANAGEMENT FUNCTIONS
# ============================================================================

add_openvpn_client() {
    local client_name=$1
    
    print_info "Adding OpenVPN client: $client_name"
    
    if [ ! -d "$OPENVPN_DIR/easy-rsa" ]; then
        print_error "OpenVPN PKI not found. Run installation first."
        return 1
    fi
    
    cd "$OPENVPN_DIR/easy-rsa"
    
    # Check if client already exists
    if [ -f "$PKI_DIR/issued/${client_name}.crt" ]; then
        print_warning "Client $client_name already exists"
        return 0
    fi
    
    # Generate certificate
    print_info "Generating certificate for $client_name..."
    ./easyrsa gen-req "$client_name" nopass > /dev/null 2>&1 || {
        print_error "Failed to generate certificate request"
        return 1
    }
    
    ./easyrsa sign-req client "$client_name" nopass > /dev/null 2>&1 || {
        print_error "Failed to sign certificate"
        return 1
    }
    
    print_success "Client certificate generated"
}

generate_openvpn_config() {
    local client_name=$1
    local server_ip=${2:-$(curl -s ifconfig.me)}
    local server_port=${3:-1194}
    local proto=${4:-udp}
    
    print_info "Generating OpenVPN config for: $client_name"
    
    if [ ! -f "$PKI_DIR/issued/${client_name}.crt" ]; then
        print_error "Client certificate not found. Run 'add_openvpn_client' first."
        return 1
    fi
    
    if [ ! -f "$PKI_DIR/ca.crt" ]; then
        print_error "CA certificate not found."
        return 1
    fi
    
    mkdir -p "$CLIENTS_DIR"
    
    local config_file="$CLIENTS_DIR/${client_name}.ovpn"
    
    # Create config with inline certificates
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
    
    print_success "Config generated: $config_file"
    print_info "Client can download: $(basename $config_file)"
    
    return 0
}

list_openvpn_clients() {
    print_info "OpenVPN Clients:"
    
    if [ ! -d "$PKI_DIR/issued" ]; then
        print_warning "No clients found"
        return 0
    fi
    
    cd "$PKI_DIR/issued"
    
    echo ""
    for cert in *.crt; do
        if [ "$cert" != "server.crt" ]; then
            local client_name="${cert%.crt}"
            local config_file="$CLIENTS_DIR/${client_name}.ovpn"
            
            if [ -f "$config_file" ]; then
                echo "  ✓ $client_name (config ready)"
            else
                echo "  ✗ $client_name (missing config)"
            fi
        fi
    done
    echo ""
}

revoke_openvpn_client() {
    local client_name=$1
    
    print_info "Revoking OpenVPN client: $client_name"
    
    if [ ! -f "$PKI_DIR/issued/${client_name}.crt" ]; then
        print_error "Client certificate not found"
        return 1
    fi
    
    cd "$OPENVPN_DIR/easy-rsa"
    
    # Revoke certificate
    ./easyrsa revoke "$client_name" > /dev/null 2>&1 || {
        print_error "Failed to revoke certificate"
        return 1
    }
    
    # Generate new CRL
    ./easyrsa gen-crl > /dev/null 2>&1 || {
        print_error "Failed to generate CRL"
        return 1
    }
    
    print_success "Client revoked: $client_name"
}

export_openvpn_config() {
    local client_name=$1
    local export_path=${2:-.}
    
    print_info "Exporting config for: $client_name"
    
    local config_file="$CLIENTS_DIR/${client_name}.ovpn"
    
    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        return 1
    fi
    
    cp "$config_file" "$export_path/"
    
    print_success "Config exported to: $export_path/${client_name}.ovpn"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local action=${1:-help}
    
    case "$action" in
        add)
            add_openvpn_client "${2:-}" || return 1
            generate_openvpn_config "${2:-}" "${3:-}" "${4:-1194}" "${5:-udp}" || return 1
            ;;
        config)
            generate_openvpn_config "${2:-}" "${3:-}" "${4:-1194}" "${5:-udp}" || return 1
            ;;
        list)
            list_openvpn_clients
            ;;
        revoke)
            revoke_openvpn_client "${2:-}" || return 1
            ;;
        export)
            export_openvpn_config "${2:-}" "${3:-.}" || return 1
            ;;
        help|*)
            echo "Usage: $0 <action> [args]"
            echo ""
            echo "Actions:"
            echo "  add <name>                    - Add new client"
            echo "  config <name> [ip] [port]     - Generate config file"
            echo "  list                          - List all clients"
            echo "  revoke <name>                 - Revoke client access"
            echo "  export <name> [path]          - Export config to path"
            echo ""
            echo "Examples:"
            echo "  $0 add client1"
            echo "  $0 list"
            echo "  $0 export client1 /tmp/"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
