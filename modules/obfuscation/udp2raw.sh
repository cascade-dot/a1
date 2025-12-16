#!/bin/bash
# modules/obfuscation/udp2raw.sh - UDP в TCP с шифрованием

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly UDP2RAW_DIR="/etc/udp2raw"
readonly CONFIG_FILE="$UDP2RAW_DIR/config.conf"
readonly DEFAULT_PORT=443
readonly DEFAULT_CIPHER="xor"
readonly DEFAULT_PASSWORD_LENGTH=32

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

install_udp2raw() {
    print_info "Установка udp2raw...")
    
    # Определяем архитектуру
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm" ;;
        *) ARCH="amd64" ;;
    esac
    
    # Скачиваем udp2raw
    local url="https://github.com/wangyu-/udp2raw-tunnel/releases/download/20230206.0/udp2raw_binaries.tar.gz"
    
    wget -O /tmp/udp2raw.tar.gz "$url"
    tar -xzf /tmp/udp2raw.tar.gz -C /tmp/
    
    # Находим правильный бинарник
    local binary_path=$(find /tmp -name "udp2raw_${ARCH}" -type f | head -1)
    
    if [ -z "$binary_path" ]; then
        # Пробуем собрать из исходников
        print_info "Компиляция udp2raw из исходников...")
        
        apt-get update
        apt-get install -y build-essential git
        
        git clone https://github.com/wangyu-/udp2raw-tunnel.git /tmp/udp2raw-src
        cd /tmp/udp2raw-src
        make
        
        binary_path="/tmp/udp2raw-src/udp2raw"
    fi
    
    # Копируем бинарник
    cp "$binary_path" /usr/local/bin/udp2raw
    chmod +x /usr/local/bin/udp2raw
    
    # Создаем директории
    mkdir -p "$UDP2RAW_DIR" /var/log/udp2raw
    
    print_success "udp2raw установлен")
}

generate_password() {
    local length=${1:-$DEFAULT_PASSWORD_LENGTH}
    
    # Генерируем случайный пароль
    local password=$(openssl rand -base64 48 | tr -d '/+=' | cut -c1-"$length")
    
    echo "$password"
}

configure_udp2raw_server() {
    local listen_port=$1
    local target_port=$2
    local password=$3
    local cipher=$4
    
    print_info "Конфигурация udp2raw сервера...")
    print_info "Режим: UDP -> TCP (faketcp)")
    print_info "Порт: $listen_port -> 127.0.0.1:$target_port")
    
    # Создаем конфиг
    cat > "$CONFIG_FILE" << EOF
# UDP2Raw Server Configuration
SERVER_MODE=true
LISTEN_PORT=$listen_port
TARGET_PORT=$target_port
PASSWORD=$password
CIPHER_MODE=$cipher
RAW_MODE=faketcp
LOG_LEVEL=3
LOG_FILE=/var/log/udp2raw/server.log
AUTO_RESTART=true
EOF
    
    # Создаем скрипт запуска
    cat > "$UDP2RAW_DIR/start-server.sh" << EOF
#!/bin/bash
# UDP2Raw Server Startup Script

/usr/local/bin/udp2raw \\
    -s \\
    -l 0.0.0.0:$listen_port \\
    -r 127.0.0.1:$target_port \\
    --raw-mode faketcp \\
    -k "$password" \\
    --cipher-mode $cipher \\
    --log-level 3 \\
    --log-file /var/log/udp2raw/server.log \\
    --disable-color \\
    --fix-gro \\
    --seq-mode 3 \\
    \$@
EOF
    
    chmod +x "$UDP2RAW_DIR/start-server.sh"
    
    print_success "Конфигурация сервера создана")
    print_info "Пароль: $password")
    print_info "Шифрование: $cipher")
}

configure_udp2raw_client() {
    local server_ip=$1
    local server_port=$2
    local local_port=$3
    local password=$4
    local cipher=$5
    
    print_info "Конфигурация udp2raw клиента...")
    
    cat > "$UDP2RAW_DIR/client-config.conf" << EOF
# UDP2Raw Client Configuration
SERVER_IP=$server_ip
SERVER_PORT=$server_port
LOCAL_PORT=$local_port
PASSWORD=$password
CIPHER_MODE=$cipher
RAW_MODE=faketcp
EOF
    
    cat > "$UDP2RAW_DIR/start-client.sh" << EOF
#!/bin/bash
# UDP2Raw Client Startup Script

/usr/local/bin/udp2raw \\
    -c \\
    -l 0.0.0.0:$local_port \\
    -r $server_ip:$server_port \\
    --raw-mode faketcp \\
    -k "$password" \\
    --cipher-mode $cipher \\
    --log-level 3 \\
    --log-file /var/log/udp2raw/client.log \\
    --disable-color \\
    --fix-gro \\
    --seq-mode 3 \\
    \$@
EOF
    
    chmod +x "$UDP2RAW_DIR/start-client.sh"
    
    # Генерация инструкции для клиента
    cat > "$UDP2RAW_DIR/client-instructions.txt" << EOF
# Инструкция по настройке udp2raw клиента

1. Установите udp2raw на клиенте:
   git clone https://github.com/wangyu-/udp2raw-tunnel.git
   cd udp2raw-tunnel
   make

2. Запустите клиент:
   ./udp2raw -c -l 0.0.0.0:3333 -r $server_ip:$server_port --raw-mode faketcp -k "$password" --cipher-mode $cipher

3. Настройте WireGuard/Xray для работы через localhost:3333

Параметры:
  Сервер: $server_ip:$server_port
  Пароль: $password
  Шифрование: $cipher
  Режим: faketcp
EOF
    
    print_success "Клиентская конфигурация создана")
}

setup_systemd_service() {
    print_info "Настройка systemd службы...")
    
    cat > /etc/systemd/system/udp2raw.service << EOF
[Unit]
Description=UDP2Raw Tunnel Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=$UDP2RAW_DIR/start-server.sh
Restart=always
RestartSec=3
LimitNOFILE=65536
LimitNPROC=65536

# Улучшенные настройки безопасности
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadOnlyDirectories=/

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable udp2raw.service
    
    print_success "Systemd служба настроена")
}

setup_firewall() {
    local port=$1
    
    print_info "Настройка фаервола для порта $port...")
    
    # Для faketcp режима нужны оба протокола
    if command -v ufw > /dev/null; then
        ufw allow $port/tcp comment "UDP2Raw faketcp"
        ufw allow $port/udp comment "UDP2Raw (резервный)"
        ufw reload
    elif command -v firewall-cmd > /dev/null; then
        firewall-cmd --permanent --add-port=$port/tcp
        firewall-cmd --permanent --add-port=$port/udp
        firewall-cmd --reload
    fi
    
    print_success "Фаервол настроен")
}

optimize_kernel_settings() {
    print_info "Оптимизация ядра для udp2raw...")
    
    # Увеличиваем размеры буферов
    sysctl -w net.core.rmem_max=134217728 > /dev/null 2>&1
    sysctl -w net.core.wmem_max=134217728 > /dev/null 2>&1
    sysctl -w net.core.rmem_default=1048576 > /dev/null 2>&1
    sysctl -w net.core.wmem_default=1048576 > /dev/null 2>&1
    
    # Оптимизации для TCP (faketcp режим)
    sysctl -w net.ipv4.tcp_tw_reuse=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_fin_timeout=15 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 > /dev/null 2>&1
    
    # Увеличиваем лимиты файловых дескрипторов
    echo "root soft nofile 65536" >> /etc/security/limits.conf
    echo "root hard nofile 65536" >> /etc/security/limits.conf
    
    print_success "Настройки ядра оптимизированы")
}

show_connection_info() {
    local server_ip=$(curl -s ifconfig.me)
    local listen_port=$(grep "LISTEN_PORT" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_PORT")
    local target_port=$(grep "TARGET_PORT" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || echo "51820")
    local password=$(grep "PASSWORD" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || echo "не найден")
    local cipher=$(grep "CIPHER_MODE" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_CIPHER")
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}          UDP2RAW (UDP → TCP) НАСТРОЕН!                        ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}▸ СЕРВЕРНАЯ КОНФИГУРАЦИЯ:${NC}"
    echo -e "  Сервер:       ${YELLOW}$server_ip${NC}"
    echo -e "  Порт:         ${YELLOW}$listen_port (TCP)${NC}"
    echo -e "  Назначение:   ${YELLOW}127.0.0.1:$target_port (UDP)${NC}"
    echo -e "  Режим:        ${YELLOW}faketcp${NC}"
    echo -e "  Шифрование:   ${YELLOW}$cipher${NC}"
    echo -e "  Пароль:       ${YELLOW}$password${NC}"
    
    echo -e "\n${CYAN}▸ КЛИЕНТСКАЯ НАСТРОЙКА:${NC}"
    echo -e "  Команда запуска клиента:"
    echo -e "  ${WHITE}udp2raw -c -l 0.0.0.0:3333 \\\\"
    echo -e "    -r $server_ip:$listen_port \\\\"
    echo -e "    --raw-mode faketcp \\\\"
    echo -e "    -k \"$password\" \\\\"
    echo -e "    --cipher-mode $cipher${NC}"
    
    echo -e "\n${CYAN}▸ ИНТЕГРАЦИЯ С WIREGUARD:${NC}"
    echo -e "  1. Настройте WireGuard на стандартном порту 51820"
    echo -e "  2. Запустите udp2raw сервер"
    echo -e "  3. На клиенте запустите udp2raw клиент"
    echo -e "  4. В WireGuard клиенте укажите endpoint: 127.0.0.1:3333"
    
    echo -e "\n${CYAN}▸ КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
    echo -e "  Статус:    ${WHITE}systemctl status udp2raw${NC}"
    echo -e "  Запуск:    ${WHITE}systemctl start udp2raw${NC}"
    echo -e "  Остановка: ${WHITE}systemctl stop udp2raw${NC}"
    echo -e "  Логи:      ${WHITE}tail -f /var/log/udp2raw/server.log${NC}"
    
    echo -e "\n${YELLOW}⚠️  ПРЕИМУЩЕСТВА UDP2RAW:${NC}"
    echo "  • Обход блокировок UDP (маскировка под TCP)"
    echo "  • Шифрование трафика (aes128cbc, xor)"
    echo "  • Анти-replay защита"
    echo "  • Фикс проблем с MTU"
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    local listen_port=${1:-$DEFAULT_PORT}
    local target_port=${2:-51820}  # Стандартный порт WireGuard
    local cipher=${3:-$DEFAULT_CIPHER}
    
    print_info "Настройка udp2raw (UDP → TCP)...")
    print_info "Порт: $listen_port → 127.0.0.1:$target_port")
    print_info "Шифрование: $cipher")
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root")
        exit 1
    fi
    
    # Установка
    install_udp2raw
    
    # Генерация пароля
    local password=$(generate_password)
    
    # Конфигурация
    configure_udp2raw_server "$listen_port" "$target_port" "$password" "$cipher"
    configure_udp2raw_client "$(curl -s ifconfig.me)" "$listen_port" "3333" "$password" "$cipher"
    
    # Настройка системы
    setup_systemd_service
    setup_firewall "$listen_port"
    optimize_kernel_settings
    
    # Запуск службы
    systemctl start udp2raw.service
    
    # Информация
    show_connection_info
    
    print_success "udp2raw настроен!")
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [listen_port] [target_port] [cipher]"
        echo ""
        echo "Параметры:"
        echo "  listen_port   Порт для прослушивания (по умолчанию: 443)"
        echo "  target_port   Целевой UDP порт (по умолчанию: 51820 для WireGuard)"
        echo "  cipher        Метод шифрования: xor, aes128cbc (по умолчанию: xor)"
        echo ""
        echo "Примеры:"
        echo "  $0 443 51820 aes128cbc    # Для WireGuard с AES шифрованием"
        echo "  $0 53 51820 xor           # Для DNS порта с простым шифрованием"
        echo "  $0 --help"
        ;;
    *)
        main "$@"
        ;;
esac