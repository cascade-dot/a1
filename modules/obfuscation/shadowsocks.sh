#!/bin/bash
# modules/obfuscation/shadowsocks.sh - Настройка Shadowsocks 2022

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly SS_DIR="/etc/shadowsocks"
readonly CONFIG_FILE="$SS_DIR/config.json"
readonly DEFAULT_PORT=8388
readonly DEFAULT_METHOD="2022-blake3-aes-128-gcm"

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

install_shadowsocks() {
    print_info "Установка Shadowsocks-rust..."
    
    # Определяем архитектуру
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="x86_64" ;;
        aarch64) ARCH="aarch64" ;;
        *) ARCH="x86_64" ;;
    esac
    
    # Скачиваем Shadowsocks-rust
    local version=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep tag_name | cut -d'"' -f4)
    local url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/shadowsocks-${version}.${arch}-unknown-linux-musl.tar.xz"
    
    wget -O /tmp/ss-rust.tar.xz "$url"
    tar -xf /tmp/ss-rust.tar.xz -C /tmp/
    
    # Копируем бинарники
    cp /tmp/ssserver /usr/local/bin/
    cp /tmp/sslocal /usr/local/bin/
    cp /tmp/ssmanager /usr/local/bin/
    cp /tmp/ssurl /usr/local/bin/
    
    chmod +x /usr/local/bin/ssserver /usr/local/bin/sslocal /usr/local/bin/ssmanager /usr/local/bin/ssurl
    
    # Создаем директории
    mkdir -p "$SS_DIR" /var/log/shadowsocks
    
    print_success "Shadowsocks-rust установлен"
}

generate_ss2022_keys() {
    print_info "Генерация ключей Shadowsocks 2022..."
    
    # Генерируем PSK для метода 2022
    local psk=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    
    # Сохраняем ключ
    echo "$psk" > "$SS_DIR/psk.txt"
    chmod 600 "$SS_DIR/psk.txt"
    
    print_success "Ключ PSK сгенерирован")
    print_info "PSK: $psk"
    
    echo "$psk"
}

configure_shadowsocks() {
    local port=$1
    local method=$2
    local password=$3
    local server_ip=$(curl -s ifconfig.me)
    
    print_info "Конфигурация Shadowsocks сервера...")
    
    # Для методов 2022 используем PSK, для старых - пароль
    local config_method="$method"
    local config_password="$password"
    
    if [[ "$method" == 2022* ]]; then
        config_password=""  # Методы 2022 используют только PSK
    fi
    
    # Создаем конфиг
    cat > "$CONFIG_FILE" << EOF
{
    "server": "0.0.0.0",
    "server_port": $port,
    "method": "$config_method",
    "password": "$config_password",
    "mode": "tcp_and_udp",
    "fast_open": true,
    "no_delay": true,
    "nofile": 51200,
    "timeout": 300,
    "ipv6_first": false,
    "nameserver": "1.1.1.1",
    "plugin": "",
    "plugin_opts": "",
    "reuse_port": true,
    "tcp_keep_alive": 15,
    "tcp_max_orphans": 1024,
    "tcp_syncookies": true,
    "tcp_fastopen": 3,
    "udp_timeout": 300,
    "udp_max_associations": 1024,
    "log": {
        "level": 2,
        "config": {
            "log_file": "/var/log/shadowsocks/server.log",
            "log_max_files": 3,
            "log_size_limit": 10485760
        }
    }
}
EOF
    
    # Для методов 2022 добавляем PSK в отдельный файл
    if [[ "$method" == 2022* ]]; then
        cat > "$SS_DIR/server-config.json" << EOF
{
    "servers": [
        {
            "server": "0.0.0.0",
            "server_port": $port,
            "method": "$method",
            "password": "$password",
            "plugin": "",
            "plugin_opts": "",
            "mode": "tcp_and_udp"
        }
    ],
    "local_port": 1080,
    "local_address": "127.0.0.1"
}
EOF
    fi
    
    print_success "Shadowsocks сконфигурирован")
}

setup_systemd_service() {
    print_info "Настройка systemd службы...")
    
    cat > /etc/systemd/system/shadowsocks.service << EOF
[Unit]
Description=Shadowsocks-rust Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ssserver -c $CONFIG_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable shadowsocks.service
    
    print_success "Systemd служба настроена")
}

setup_firewall() {
    local port=$1
    
    print_info "Настройка фаервола для порта $port...")
    
    if command -v ufw > /dev/null; then
        ufw allow $port/tcp comment "Shadowsocks TCP"
        ufw allow $port/udp comment "Shadowsocks UDP"
        ufw reload
    elif command -v firewall-cmd > /dev/null; then
        firewall-cmd --permanent --add-port=$port/tcp
        firewall-cmd --permanent --add-port=$port/udp
        firewall-cmd --reload
    fi
    
    print_success "Фаервол настроен")
}

generate_client_configs() {
    local server_ip=$1
    local port=$2
    local method=$3
    local password=$4
    
    print_info "Генерация клиентских конфигураций...")
    
    # Конфиг для Shadowsocks клиентов
    cat > "$SS_DIR/client.json" << EOF
{
    "server": "$server_ip",
    "server_port": $port,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "$password",
    "method": "$method",
    "timeout": 300,
    "fast_open": true,
    "mode": "tcp_and_udp",
    "plugin": "",
    "plugin_opts": ""
}
EOF
    
    # Генерация SS URL (для импорта в клиенты)
    local encoded_password=$(echo -n "$password" | base64 | tr -d '\n')
    local ss_url="ss://$(echo -n "$method:$password" | base64 | tr -d '\n')@$server_ip:$port#Shadowsocks"
    
    echo "$ss_url" > "$SS_DIR/ss-url.txt"
    
    # QR код
    if command -v qrencode > /dev/null; then
        qrencode -o "$SS_DIR/client-qr.png" -t PNG "$ss_url"
        qrencode -t ansiutf8 "$ss_url"
    fi
    
    print_success "Клиентские конфиги созданы")
    print_info "SS URL: $ss_url")
    print_info "Конфиг: $SS_DIR/client.json")
    print_info "QR код: $SS_DIR/client-qr.png")
}

show_connection_info() {
    local server_ip=$(curl -s ifconfig.me)
    local port=$(jq -r '.server_port' "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
    local method=$(jq -r '.method' "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_METHOD")
    local password=$(cat "$SS_DIR/psk.txt" 2>/dev/null || echo "")
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}          SHADOWSOCKS 2022 НАСТРОЕН!                           ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}▸ ПАРАМЕТРЫ ПОДКЛЮЧЕНИЯ:${NC}"
    echo -e "  Сервер:    ${YELLOW}$server_ip${NC}"
    echo -e "  Порт:      ${YELLOW}$port${NC}"
    echo -e "  Метод:     ${YELLOW}$method${NC}"
    
    if [ -n "$password" ]; then
        echo -e "  PSK:       ${YELLOW}$password${NC}"
    fi
    
    echo -e "\n${CYAN}▸ ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo -e "  1. Установите Shadowsocks клиент"
    echo -e "  2. Импортируйте SS URL из: ${WHITE}$SS_DIR/ss-url.txt${NC}"
    echo -e "  3. Или отсканируйте QR-код: ${WHITE}$SS_DIR/client-qr.png${NC}"
    
    echo -e "\n${CYAN}▸ КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
    echo -e "  Статус:    ${WHITE}systemctl status shadowsocks${NC}"
    echo -e "  Запуск:    ${WHITE}systemctl start shadowsocks${NC}"
    echo -e "  Остановка: ${WHITE}systemctl stop shadowsocks${NC}"
    echo -e "  Логи:      ${WHITE}tail -f /var/log/shadowsocks/server.log${NC}"
    
    echo -e "\n${YELLOW}⚠️  ВАЖНО:${NC}"
    echo "  1. Shadowsocks 2022 требует поддержки в клиенте"
    echo "  2. Рекомендуется использовать 2022-blake3-aes-128-gcm"
    echo "  3. Работает через TCP и UDP"
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    local port=${1:-$DEFAULT_PORT}
    local method=${2:-$DEFAULT_METHOD}
    
    print_info "Настройка Shadowsocks 2022...")
    print_info "Порт: $port, Метод: $method")
    
    # Проверка root
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root")
        exit 1
    fi
    
    # Установка
    install_shadowsocks
    
    # Генерация ключей
    local password=""
    if [[ "$method" == 2022* ]]; then
        password=$(generate_ss2022_keys)
    else
        password=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-12)
        echo "$password" > "$SS_DIR/password.txt"
        chmod 600 "$SS_DIR/password.txt"
    fi
    
    # Настройка
    local server_ip=$(curl -s ifconfig.me)
    configure_shadowsocks "$port" "$method" "$password"
    setup_systemd_service
    setup_firewall "$port"
    generate_client_configs "$server_ip" "$port" "$method" "$password"
    
    # Запуск службы
    systemctl start shadowsocks.service
    
    # Информация
    show_connection_info
    
    print_success "Shadowsocks 2022 настроен!")
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [порт] [метод]"
        echo ""
        echo "Доступные методы:"
        echo "  2022-blake3-aes-128-gcm (рекомендуется)"
        echo "  2022-blake3-aes-256-gcm"
        echo "  aes-256-gcm"
        echo "  chacha20-ietf-poly1305"
        echo "  xchacha20-ietf-poly1305"
        echo ""
        echo "Примеры:"
        echo "  $0 8388 2022-blake3-aes-128-gcm"
        echo "  $0 443 aes-256-gcm"
        echo "  $0 --help"
        ;;
    *)
        main "$@"
        ;;
esac