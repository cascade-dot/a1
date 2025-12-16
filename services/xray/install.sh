#!/bin/bash
# services/xray/install.sh - Xray Proxy Installation

set -euo pipefail

XRAY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$XRAY_SCRIPT_DIR/../../utils/colors.sh"
source "$XRAY_SCRIPT_DIR/../../utils/logger.sh"
source "$XRAY_SCRIPT_DIR/../../utils/validators.sh"

readonly INSTALL_DIR="/etc/xray"
readonly CONFIG_FILE="$INSTALL_DIR/config.json"
readonly SERVICE_FILE="/etc/systemd/system/xray.service"

install_xray() {
    log_section_start "Installing Xray"
    
    print_info "Installing Xray-core proxy..."
    
    # Определяем архитектуру
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        *) ARCH="64" ;;
    esac
    
    # Скачиваем Xray
    local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH}.zip"
    
    print_info "Downloading Xray from GitHub..."
    wget -O /tmp/xray.zip "$xray_url" > /dev/null 2>&1
    unzip -o /tmp/xray.zip -d /tmp/xray-extract > /dev/null
    
    # Создаем директории
    mkdir -p "$INSTALL_DIR" /var/log/xray
    
    # Копируем файлы
    cp /tmp/xray-extract/xray /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    # Копируем geoip и geosite
    cp /tmp/xray-extract/geoip.dat "$INSTALL_DIR/" 2>/dev/null || true
    cp /tmp/xray-extract/geosite.dat "$INSTALL_DIR/" 2>/dev/null || true
    
    # Очищаем временные файлы
    rm -rf /tmp/xray.zip /tmp/xray-extract
    
    print_success "Xray installed successfully"
    log_section_end "Installing Xray" "success"
}

configure_xray() {
    local inbound_port=${1:-443}
    local protocol=${2:-vless}
    
    log_section_start "Configuring Xray"
    
    print_info "Creating Xray configuration..."
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # Конфигурация с поддержкой VLESS и TLS
    cat > "$CONFIG_FILE" << EOF
{
    "log": {
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log",
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $inbound_port,
            "protocol": "$protocol",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "$INSTALL_DIR/cert.pem",
                            "keyFile": "$INSTALL_DIR/key.pem"
                        }
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": []
    }
}
EOF
    
    chmod 600 "$CONFIG_FILE"
    print_success "Xray configured"
    log_section_end "Configuring Xray" "success"
}

setup_xray_service() {
    log_section_start "Setting up Xray Service"
    
    # Создаем systemd сервис
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Xray Core Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray -c /etc/xray/config.json
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=xray

LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable xray
    systemctl start xray
    
    print_success "Xray service created and started"
    log_section_end "Setting up Xray Service" "success"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_root
    install_xray
    configure_xray 443 "vless"
    setup_xray_service
fi
