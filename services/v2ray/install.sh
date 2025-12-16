#!/bin/bash
# services/v2ray/install.sh - V2Ray Proxy Installation

set -euo pipefail

V2R_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$V2R_SCRIPT_DIR/../../utils/colors.sh"
source "$V2R_SCRIPT_DIR/../../utils/logger.sh"
source "$V2R_SCRIPT_DIR/../../utils/validators.sh"

readonly INSTALL_DIR="/etc/v2ray"
readonly CONFIG_FILE="$INSTALL_DIR/config.json"
readonly SERVICE_FILE="/etc/systemd/system/v2ray.service"

install_v2ray() {
    log_section_start "Installing V2Ray"
    
    print_info "Installing V2Ray proxy..."
    
    # Определяем архитектуру
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        *) ARCH="64" ;;
    esac
    
    # Скачиваем V2Ray
    local v2ray_url="https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-${ARCH}.zip"
    
    print_info "Downloading V2Ray from GitHub..."
    wget -O /tmp/v2ray.zip "$v2ray_url" > /dev/null 2>&1
    unzip -o /tmp/v2ray.zip -d /tmp/v2ray-extract > /dev/null
    
    # Создаем директории
    mkdir -p "$INSTALL_DIR" /var/log/v2ray
    
    # Копируем файлы
    cp /tmp/v2ray-extract/v2ray /usr/local/bin/
    chmod +x /usr/local/bin/v2ray
    
    # Копируем geoip и geosite для маршрутизации
    cp /tmp/v2ray-extract/geoip.dat "$INSTALL_DIR/" 2>/dev/null || true
    cp /tmp/v2ray-extract/geosite.dat "$INSTALL_DIR/" 2>/dev/null || true
    
    # Очищаем временные файлы
    rm -rf /tmp/v2ray.zip /tmp/v2ray-extract
    
    print_success "V2Ray installed successfully"
    log_section_end "Installing V2Ray" "success"
}

configure_v2ray() {
    local inbound_port=${1:-10086}
    local protocol=${2:-vmess}
    
    log_section_start "Configuring V2Ray"
    
    print_info "Creating V2Ray configuration..."
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # Базовая конфигурация
    cat > "$CONFIG_FILE" << EOF
{
    "log": {
        "access": "/var/log/v2ray/access.log",
        "error": "/var/log/v2ray/error.log",
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $inbound_port,
            "protocol": "$protocol",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "level": 1,
                        "alterId": 32
                    }
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        },
        {
            "protocol": "blackhole",
            "settings": {},
            "tag": "blocked"
        }
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:private"
                ],
                "outboundTag": "blocked"
            }
        ]
    }
}
EOF
    
    chmod 600 "$CONFIG_FILE"
    print_success "V2Ray configured"
    log_section_end "Configuring V2Ray" "success"
}

setup_v2ray_service() {
    log_section_start "Setting up V2Ray Service"
    
    # Создаем systemd сервис
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=V2Ray Proxy Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/v2ray -c /etc/v2ray/config.json
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=v2ray

LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable v2ray
    systemctl start v2ray
    
    print_success "V2Ray service created and started"
    log_section_end "Setting up V2Ray Service" "success"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_root
    install_v2ray
    configure_v2ray 10086 "vmess"
    setup_v2ray_service
fi
