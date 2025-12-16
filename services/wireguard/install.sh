#!/bin/bash
# services/wireguard/install.sh - Установка WireGuard сервера

set -euo pipefail

# Подключаем утилиты
WG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$WG_SCRIPT_DIR/../../utils/colors.sh"
source "$WG_SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly CONFIG_DIR="/etc/wireguard"
readonly CONFIG_FILE="$CONFIG_DIR/wg0.conf"
readonly BACKUP_DIR="/var/backups/wireguard"
readonly SERVICE_NAME="wg-quick@wg0"
readonly DEFAULT_PORT=51820
readonly DEFAULT_SUBNET="10.8.0.0/24"

# ------------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ------------------------------------------------------------------------------

generate_keys() {
    print_info "Генерация ключей WireGuard..."
    
    mkdir -p "$CONFIG_DIR"
    cd "$CONFIG_DIR"
    
    # Генерация ключей сервера
    umask 077
    wg genkey | tee server-private.key | wg pubkey > server-public.key
    wg genpsk > server-preshared.key 2>/dev/null || true
    
    SERVER_PRIVATE_KEY=$(cat server-private.key)
    SERVER_PUBLIC_KEY=$(cat server-public.key)
    
    print_success "Ключи сгенерированы"
    print_info "Публичный ключ сервера: $SERVER_PUBLIC_KEY"
}

configure_server() {
    local port=${1:-$DEFAULT_PORT}
    local subnet=${2:-$DEFAULT_SUBNET}
    
    print_info "Конфигурация WireGuard сервера..."
    
    # Определяем IP сервера в подсети
    local server_ip=$(echo "$subnet" | sed 's/\.0\/.*$/.1/')
    
    # Создаем конфиг сервера
    cat > "$CONFIG_FILE" << EOF
[Interface]
Address = $server_ip/24
ListenPort = $port
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
SaveConfig = true

# Клиенты будут добавляться здесь
EOF
    
    print_success "Конфигурация сервера создана"
    print_info "Сервер будет слушать порт: $port"
    print_info "Подсеть: $subnet (сервер: $server_ip)"
}

setup_firewall() {
    local port=${1:-$DEFAULT_PORT}
    
    print_info "Настройка фаервола для порта $port..."
    
    # Определяем тип фаервола
    if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow $port/udp comment "WireGuard VPN"
        ufw reload
        print_success "UFW настроен"
        
    elif command -v firewall-cmd > /dev/null; then
        firewall-cmd --permanent --add-port=$port/udp
        firewall-cmd --reload
        print_success "Firewalld настроен"
        
    else
        # Базовые правила iptables
        iptables -A INPUT -p udp --dport $port -j ACCEPT
        iptables -A FORWARD -i wg0 -j ACCEPT
        iptables -A FORWARD -o wg0 -j ACCEPT
        iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
        print_success "IPTables правила добавлены"
    fi
}

enable_ip_forwarding() {
    print_info "Включение IP forwarding..."
    
    # Проверяем и включаем
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    # Применяем изменения
    sysctl -p > /dev/null 2>&1
    
    print_success "IP forwarding включен"
}

setup_systemd_service() {
    print_info "Настройка systemd службы..."
    
    # Проверяем наличие службы
    if [ ! -f "/etc/systemd/system/wg-quick@.service" ]; then
        # Создаем базовую службу
        cat > /etc/systemd/system/wg-quick@.service << EOF
[Unit]
Description=WireGuard via wg-quick(8) for %I
After=network-online.target nss-lookup.target
Wants=network-online.target nss-lookup.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/wg-quick up %i
ExecStop=/usr/bin/wg-quick down %i
ExecReload=/bin/bash -c 'exec /usr/bin/wg syncconf %i <(wg-quick strip %i)'

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # Включаем автозапуск
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    print_success "Systemd служба настроена"
}

create_client() {
    local client_name=${1:-"client01"}
    local subnet=${2:-$DEFAULT_SUBNET}
    
    print_info "Создание клиента: $client_name..."
    
    # Генерируем IP клиента (последний октет увеличиваем)
    local client_number=$(ls -1 "$CONFIG_DIR/clients/" 2>/dev/null | wc -l)
    client_number=$((client_number + 2))  # +2 потому что сервер на .1
    
    local client_ip=$(echo "$subnet" | sed "s/\.0\/.*$/.$client_number/")
    
    # Генерация ключей клиента
    wg genkey | tee "$CONFIG_DIR/${client_name}-private.key" | wg pubkey > "$CONFIG_DIR/${client_name}-public.key"
    local client_private_key=$(cat "$CONFIG_DIR/${client_name}-private.key")
    local client_public_key=$(cat "$CONFIG_DIR/${client_name}-public.key")
    
    # Добавляем клиента в конфиг сервера
    cat >> "$CONFIG_FILE" << EOF

[Peer]
# $client_name
PublicKey = $client_public_key
AllowedIPs = $client_ip/32
PersistentKeepalive = 25
EOF
    
    # Создаем конфиг клиента
    mkdir -p "$CONFIG_DIR/clients"
    
    # Получаем публичный IP сервера
    local server_public_ip=$(curl -s ifconfig.me)
    local server_port=$(grep "ListenPort" "$CONFIG_FILE" | awk '{print $3}')
    
    cat > "$CONFIG_DIR/clients/${client_name}.conf" << EOF
[Interface]
PrivateKey = $client_private_key
Address = $client_ip/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $server_public_ip:$server_port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    # Перезагружаем WireGuard
    wg syncconf wg0 <(wg-quick strip wg0)
    
    print_success "Клиент $client_name создан"
    print_info "IP клиента: $client_ip"
    print_info "Конфиг: $CONFIG_DIR/clients/${client_name}.conf"
}

generate_qr_code() {
    local client_name=${1:-"client01"}
    
    if [ ! -f "$CONFIG_DIR/clients/${client_name}.conf" ]; then
        print_error "Конфиг клиента $client_name не найден"
        return 1
    fi
    
    if command -v qrencode > /dev/null; then
        print_info "Генерация QR-кода для $client_name..."
        
        qrencode -t ansiutf8 < "$CONFIG_DIR/clients/${client_name}.conf"
        qrencode -o "$CONFIG_DIR/clients/${client_name}.png" \
            -t PNG < "$CONFIG_DIR/clients/${client_name}.conf"
        
        print_success "QR-код создан: $CONFIG_DIR/clients/${client_name}.png"
    else
        print_warning "qrencode не установлен. Установите: apt-get install qrencode"
    fi
}

setup_backup() {
    print_info "Настройка автоматических бэкапов..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Создаем скрипт бэкапа
    cat > /usr/local/bin/wg-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/wireguard"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/wireguard-backup-$DATE.tar.gz"

# Создаем бэкап конфигов
tar -czf "$BACKUP_FILE" /etc/wireguard /usr/local/bin/wg-*.sh 2>/dev/null

# Удаляем старые бэкапы (храним 7 дней)
find "$BACKUP_DIR" -name "wireguard-backup-*.tar.gz" -mtime +7 -delete

echo "Бэкап создан: $BACKUP_FILE"
EOF
    
    chmod +x /usr/local/bin/wg-backup.sh
    
    # Добавляем в cron
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/wg-backup.sh > /dev/null 2>&1") | crontab -
    
    print_success "Автоматические бэкапы настроены"
}

show_status() {
    print_info "=== WireGuard Статус ==="
    
    # Проверяем службу
    if systemctl is-active "$SERVICE_NAME" > /dev/null; then
        print_success "Служба активна"
    else
        print_error "Служба не активна"
    fi
    
    # Показываем интерфейс
    if ip link show wg0 > /dev/null 2>&1; then
        print_success "Интерфейс wg0 существует"
        echo ""
        wg show wg0
    else
        print_error "Интерфейс wg0 не найден"
    fi
    
    # Показываем клиентов
    local client_count=$(ls -1 "$CONFIG_DIR/clients/" 2>/dev/null | wc -l)
    print_info "Количество клиентов: $client_count"
}

# ------------------------------------------------------------------------------
# ГЛАВНОЕ МЕНЮ
# ------------------------------------------------------------------------------

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               WIREGUARD INSTALLER                            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${GREEN}[1]${NC} Полная установка WireGuard"
    echo -e "${GREEN}[2]${NC} Создать нового клиента"
    echo -e "${GREEN}[3]${NC} Сгенерировать QR-код для клиента"
    echo -e "${GREEN}[4]${NC} Показать статус"
    echo -e "${GREEN}[5]${NC} Настроить бэкапы"
    echo -e "${GREEN}[6]${NC} Перезапустить WireGuard"
    echo -e "${RED}[7]${NC} Удалить WireGuard"
    echo -e "${WHITE}[0]${NC} Выход\n"
    
    read -p "Выберите действие (0-7): " choice
    
    case $choice in
        1)
            read -p "Порт WireGuard [$DEFAULT_PORT]: " port
            port=${port:-$DEFAULT_PORT}
            
            read -p "Подсеть [$DEFAULT_SUBNET]: " subnet
            subnet=${subnet:-$DEFAULT_SUBNET}
            
            generate_keys
            configure_server "$port" "$subnet"
            setup_firewall "$port"
            enable_ip_forwarding
            setup_systemd_service
            create_client "client01" "$subnet"
            setup_backup
            
            # Запускаем службу
            systemctl start "$SERVICE_NAME"
            
            print_success "WireGuard установлен и запущен!"
            show_status
            ;;
            
        2)
            read -p "Имя клиента: " client_name
            if [ -z "$client_name" ]; then
                print_error "Имя клиента не может быть пустым"
                return
            fi
            
            create_client "$client_name"
            generate_qr_code "$client_name"
            ;;
            
        3)
            read -p "Имя клиента [client01]: " client_name
            client_name=${client_name:-"client01"}
            
            generate_qr_code "$client_name"
            ;;
            
        4)
            show_status
            ;;
            
        5)
            setup_backup
            ;;
            
        6)
            systemctl restart "$SERVICE_NAME"
            print_success "WireGuard перезапущен"
            ;;
            
        7)
            read -p "Вы уверены? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                systemctl stop "$SERVICE_NAME"
                systemctl disable "$SERVICE_NAME"
                rm -rf "$CONFIG_DIR" "$BACKUP_DIR"
                print_success "WireGuard удален"
            fi
            ;;
            
        0)
            echo "Выход."
            exit 0
            ;;
            
        *)
            print_error "Неверный выбор"
            ;;
    esac
    
    echo ""
    read -p "Нажмите Enter для продолжения..." -n 1
    show_menu
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    # Проверяем root
    if [[ $EUID -ne 0 ]]; then
        print_error "Запустите скрипт с правами root"
        exit 1
    fi
    
    # Проверяем WireGuard
    if ! command -v wg > /dev/null; then
        print_info "Установка WireGuard..."
        
        if [[ -f /etc/debian_version ]]; then
            apt-get update
            apt-get install -y wireguard wireguard-tools
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y wireguard-tools
        else
            print_error "Не удалось установить WireGuard"
            exit 1
        fi
    fi
    
    # Показываем меню
    show_menu
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [опции]"
        echo ""
        echo "Опции:"
        echo "  --install           Быстрая установка"
        echo "  --client <имя>      Создать клиента"
        echo "  --status            Показать статус"
        echo "  --menu              Интерактивное меню (по умолчанию)"
        echo "  --help              Показать эту справку"
        ;;
    "--install")
        generate_keys
        configure_server
        setup_firewall
        enable_ip_forwarding
        setup_systemd_service
        create_client "client01"
        systemctl start "$SERVICE_NAME"
        print_success "WireGuard установлен"
        ;;
    "--client")
        if [ -z "$2" ]; then
            print_error "Укажите имя клиента"
            exit 1
        fi
        create_client "$2"
        ;;
    "--status")
        show_status
        ;;
    "--menu"|"")
        main
        ;;
    *)
        print_error "Неизвестная опция: $1"
        echo "Используйте: $0 --help"
        exit 1
        ;;
esac