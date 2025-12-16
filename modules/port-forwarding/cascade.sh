#!/bin/bash
# modules/port-forwarding/cascade.sh - Настройка каскадного проброса

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly CASCADE_DIR="/etc/cascade-vpn/cascade"
readonly SCRIPT_NAME="cascade-manager.sh"

# ------------------------------------------------------------------------------
# ФУНКЦИИ КАСКАДНОГО ПРОБРОСА
# ------------------------------------------------------------------------------

setup_cascade_tunnel() {
    local local_ip=$1
    local remote_ip=$2
    local forward_port=$3
    local protocol=${4:-"tcp"}
    
    print_info "Настройка каскадного туннеля:"
    print_info "  Локальный сервер: $local_ip"
    print_info "  Удаленный сервер: $remote_ip"
    print_info "  Порт: $forward_port/$protocol"
    
    # Создаем директорию для конфигов
    mkdir -p "$CASCADE_DIR"
    
    # Конфигурация каскада
    local config_file="$CASCADE_DIR/tunnel_${forward_port}.conf"
    
    cat > "$config_file" << EOF
# Конфигурация каскадного туннеля
LOCAL_IP=$local_ip
REMOTE_IP=$remote_ip
FORWARD_PORT=$forward_port
PROTOCOL=$protocol
CREATED=$(date +%Y-%m-%d\ %H:%M:%S)

# Директивы iptables/nftables
IPTABLES_RULES=(
    "-t nat -A PREROUTING -p $protocol --dport \$FORWARD_PORT -j DNAT --to-destination \$REMOTE_IP:\$FORWARD_PORT"
    "-A FORWARD -p $protocol -d \$REMOTE_IP --dport \$FORWARD_PORT -j ACCEPT"
    "-A INPUT -p $protocol --dport \$FORWARD_PORT -j ACCEPT"
)
EOF
    
    # Настраиваем проброс портов
    setup_port_forwarding "$forward_port" "$remote_ip" "$forward_port" "$protocol"
    
    # Настраиваем оптимизацию
    optimize_cascade_performance
    
    # Создаем скрипт управления
    create_cascade_manager
    
    print_success "Каскадный туннель настроен"
    print_info "Конфигурация: $config_file"
}

setup_port_forwarding() {
    local local_port=$1
    local remote_ip=$2
    local remote_port=$3
    local protocol=$4
    
    print_info "Настройка проброса порта $local_port -> $remote_ip:$remote_port"
    
    # Используем iptables
    iptables -t nat -A PREROUTING -p "$protocol" --dport "$local_port" \
        -j DNAT --to-destination "$remote_ip:$remote_port"
    
    iptables -A FORWARD -p "$protocol" -d "$remote_ip" --dport "$remote_port" \
        -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    
    iptables -A INPUT -p "$protocol" --dport "$local_port" -j ACCEPT
    
    print_success "Проброс портов настроен"
}

optimize_cascade_performance() {
    print_info "Оптимизация производительности каскада..."
    
    # TCP оптимизации
    sysctl -w net.ipv4.tcp_tw_reuse=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_fin_timeout=30 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 > /dev/null 2>&1
    
    # Размеры буферов
    sysctl -w net.core.rmem_max=134217728 > /dev/null 2>&1
    sysctl -w net.core.wmem_max=134217728 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728" > /dev/null 2>&1
    
    # BBR congestion control
    sysctl -w net.core.default_qdisc=fq > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
    
    print_success "Оптимизации применены")
}

create_cascade_manager() {
    print_info "Создание скрипта управления каскадом..."
    
    cat > "/usr/local/bin/$SCRIPT_NAME" << 'EOF'
#!/bin/bash
# Cascade VPN Manager

CONFIG_DIR="/etc/cascade-vpn/cascade"
LOG_FILE="/var/log/cascade-vpn/manager.log"

source /opt/cascade-vpn/utils/colors.sh

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               CASCADE VPN MANAGER                           ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo ""
    echo -e "${GREEN}[1]${NC} Список активных туннелей"
    echo -e "${GREEN}[2]${NC} Статус туннеля"
    echo -e "${GREEN}[3]${NC} Тестирование соединения"
    echo -e "${GREEN}[4]${NC} Перезапустить туннель"
    echo -e "${GREEN}[5]${NC} Мониторинг трафика"
    echo -e "${GREEN}[6]${NC} Логи туннеля"
    echo -e "${RED}[7]${NC} Удалить туннель"
    echo -e "${WHITE}[0]${NC} Выход"
    echo ""
}

list_tunnels() {
    echo -e "${CYAN}Активные каскадные туннели:${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    
    if [ -d "$CONFIG_DIR" ]; then
        for config in "$CONFIG_DIR"/*.conf; do
            if [ -f "$config" ]; then
                local name=$(basename "$config" .conf)
                source "$config"
                echo -e "${GREEN}○${NC} $name"
                echo "  Локальный порт: $FORWARD_PORT"
                echo "  Удаленный сервер: $REMOTE_IP"
                echo "  Протокол: $PROTOCOL"
                echo ""
            fi
        done
    else
        echo "  Нет активных туннелей"
    fi
}

test_tunnel() {
    local port=$1
    
    echo -e "${CYAN}Тестирование туннеля на порту $port...${NC}"
    
    # Проверяем локальный порт
    if netstat -tuln | grep -q ":$port "; then
        echo -e "  ${GREEN}✓${NC} Порт $port слушается"
    else
        echo -e "  ${RED}✗${NC} Порт $port не слушается"
        return 1
    fi
    
    # Проверяем правила iptables
    if iptables -t nat -L -n | grep -q "dpt:$port"; then
        echo -e "  ${GREEN}✓${NC} Правило iptables существует"
    else
        echo -e "  ${RED}✗${NC} Правило iptables не найдено"
    fi
    
    echo -e "${GREEN}Тестирование завершено${NC}"
}

monitor_traffic() {
    local port=$1
    
    echo -e "${CYAN}Мониторинг трафика на порту $port...${NC}"
    echo "Нажмите Ctrl+C для остановки"
    echo ""
    
    # Показываем статистику
    watch -n 1 "netstat -an | grep ':$port' | awk '{print \$5}' | cut -d: -f1 | sort | uniq -c | sort -n"
}

main() {
    while true; do
        show_menu
        read -p "Выберите действие (0-7): " choice
        
        case $choice in
            1) list_tunnels ;;
            2) 
                read -p "Порт туннеля: " port
                test_tunnel "$port"
                ;;
            3)
                read -p "Порт для тестирования: " port
                test_tunnel "$port"
                ;;
            4)
                read -p "Порт туннеля: " port
                echo "Перезапуск туннеля $port..."
                # Здесь будет перезапуск
                ;;
            5)
                read -p "Порт для мониторинга: " port
                monitor_traffic "$port"
                ;;
            6)
                echo "Просмотр логов..."
                tail -f "$LOG_FILE"
                ;;
            7)
                read -p "Порт туннеля для удаления: " port
                read -p "Вы уверены? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo "Удаление туннеля $port..."
                    rm -f "$CONFIG_DIR/tunnel_${port}.conf"
                    echo "Туннель удален"
                fi
                ;;
            0)
                echo "Выход."
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор${NC}"
                ;;
        esac
        
        echo ""
        read -p "Нажмите Enter для продолжения..." -n 1
    done
}

# Запуск
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Требуются права root${NC}"
    exit 1
fi

main "$@"
EOF
    
    chmod +x "/usr/local/bin/$SCRIPT_NAME"
    
    print_success "Скрипт управления создан: /usr/local/bin/$SCRIPT_NAME"
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    print_info "Настройка каскадного проброса портов"
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root"
        exit 1
    fi
    
    # Получаем IP адреса
    local local_ip=$(hostname -I | awk '{print $1}')
    local public_ip=$(curl -s ifconfig.me)
    
    echo ""
    echo -e "${CYAN}Текущие IP адреса:${NC}"
    echo -e "  Локальный:  $local_ip"
    echo -e "  Публичный:  $public_ip"
    echo ""
    
    # Запрашиваем параметры
    read -p "Локальный порт для проброса: " forward_port
    
    if [ -z "$forward_port" ]; then
        print_error "Порт не может быть пустым"
        exit 1
    fi
    
    read -p "IP удаленного сервера: " remote_ip
    
    if [ -z "$remote_ip" ]; then
        print_error "IP не может быть пустым"
        exit 1
    fi
    
    read -p "Протокол (tcp/udp) [tcp]: " protocol
    protocol=${protocol:-"tcp"}
    
    # Настраиваем каскад
    setup_cascade_tunnel "$local_ip" "$remote_ip" "$forward_port" "$protocol"
    
    # Инструкции
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}          КАСКАДНЫЙ ТУННЕЛЬ НАСТРОЕН!                         ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Для подключения используйте:"
    echo -e "  Сервер: ${YELLOW}$public_ip${NC}"
    echo -e "  Порт:   ${YELLOW}$forward_port${NC}"
    echo -e "  Протокол: ${YELLOW}$protocol${NC}"
    echo ""
    echo -e "Управление туннелем:"
    echo -e "  ${WHITE}cascade-manager.sh${NC} - меню управления"
    echo -e "  ${WHITE}systemctl restart nftables${NC} - перезапуск"
    echo ""
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0"
        echo ""
        echo "Настройка каскадного проброса портов:"
        echo "  1. Укажите локальный порт"
        echo "  2. Укажите IP удаленного сервера"
        echo "  3. Скрипт настроит проброс и оптимизацию"
        echo ""
        echo "После настройки используйте: cascade-manager.sh"
        ;;
    *)
        main
        ;;
esac