#!/bin/bash
# modules/obfuscation/trojan-tls.sh - Настройка Trojan + TLS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly TROJAN_DIR="/etc/trojan"
readonly CONFIG_FILE="$TROJAN_DIR/config.json"
readonly DEFAULT_PORT=443

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

install_trojan() {
    print_info "Установка Trojan-Go..."
    
    # Определяем архитектуру
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) ARCH="amd64" ;;
    esac
    
    # Скачиваем Trojan-Go
    local version=$(curl -s https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest | grep tag_name | cut -d'"' -f4)
    local url="https://github.com/p4gefau1t/trojan-go/releases/download/${version}/trojan-go-linux-${ARCH}.zip"
    
    wget -O /tmp/trojan-go.zip "$url"
    unzip -o /tmp/trojan-go.zip trojan-go -d /usr/local/bin/
    chmod +x /usr/local/bin/trojan-go
    
    # Создаем директории
    mkdir -p "$TROJAN_DIR" /var/log/trojan
    
    print_success "Trojan-Go установлен"
}

configure_trojan() {
    local port=$1
    local domain=$2
    local password=$(openssl rand -base64 16)
    
    print_info "Конфигурация Trojan-Go..."
    
    # Создаем конфиг
    cat > "$CONFIG_FILE" << EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": $port,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$password"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "$TROJAN_DIR/cert.pem",
        "key": "$TROJAN_DIR/key.pem",
        "sni": "$domain",
        "alpn": [
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "curve": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "reuse_port": false,
        "fast_open": false,
        "fast_open_qlen": 20
    },
    "websocket": {
        "enabled": true,
        "path": "/$(openssl rand -hex 4)/",
        "host": "$domain"
    }
}
EOF
    
    # Сохраняем пароль
    echo "$password" > "$TROJAN_DIR/password.txt"
    chmod 600 "$TROJAN_DIR/password.txt"
    
    print_success "Trojan-Go сконфигурирован"
    print_info "Пароль: $password"
}

# Остальные функции аналогично vless-ws-tls.sh
# (setup_systemd_service, setup_firewall, generate_client_config, etc.)

main() {
    local port=${1:-$DEFAULT_PORT}
    local domain=${2:-$(curl -s ifconfig.me)}
    
    print_info "Настройка Trojan + TLS..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root"
        exit 1
    fi
    
    install_trojan
    configure_tls "$domain"  # Функция из vless-ws-tls.sh
    configure_trojan "$port" "$domain"
    
    print_success "Trojan + TLS настроен")
}

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [порт] [домен]"
        ;;
    *)
        main "$@"
        ;;
esac