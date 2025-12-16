#!/bin/bash
# modules/port-forwarding/iptables.sh - Настройка проброса портов через iptables

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly RULES_FILE="/etc/iptables/rules.v4"
readonly BACKUP_DIR="/var/backups/iptables"
readonly CONFIG_DIR="/etc/cascade-vpn/port-forwarding"

# ------------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ------------------------------------------------------------------------------

check_iptables() {
    if ! command -v iptables > /dev/null; then
        print_error "iptables не установлен"
        
        if [[ -f /etc/debian_version ]]; then
            print_info "Установка iptables..."
            apt-get update && apt-get install -y iptables iptables-persistent
        elif [[ -f /etc/redhat-release ]]; then
            print_info "Установка iptables..."
            yum install -y iptables iptables-services
        else
            print_error "Не удалось установить iptables"
            exit 1
        fi
    fi
    
    print_success "iptables доступен"
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

setup_persistent_rules() {
    print_info "Настройка сохранения правил iptables..."
    
    # Для Debian/Ubuntu
    if [[ -f /etc/debian_version ]]; then
        if ! dpkg -s iptables-persistent > /dev/null 2>&1; then
            apt-get install -y iptables-persistent
        fi
        
        # Создаем backup текущих правил
        mkdir -p "$BACKUP_DIR"
        iptables-save > "$BACKUP_DIR/iptables-backup-$(date +%Y%m%d_%H%M%S).rules"
        
    # Для RHEL/CentOS
    elif [[ -f /etc/redhat-release ]]; then
        systemctl enable iptables
        systemctl start iptables
        
        # Сохраняем текущие правила
        mkdir -p "$BACKUP_DIR"
        iptables-save > "$BACKUP_DIR/iptables-backup-$(date +%Y%m%d_%H%M%S).rules"
    fi
    
    print_success "Сохранение правил настроено"
}

# ------------------------------------------------------------------------------
# ОСНОВНЫЕ ФУНКЦИИ ПРОБРОСА
# ------------------------------------------------------------------------------

add_port_forward() {
    local local_port=$1
    local remote_ip=$2
    local remote_port=$3
    local protocol=${4:-"tcp"}
    
    print_info "Добавление проброса порта: $local_port:$protocol -> $remote_ip:$remote_port"
    
    # Проверяем, что порт не занят
    if netstat -tuln | grep -q ":$local_port "; then
        print_warning "Порт $local_port уже занят"
        read -p "Продолжить? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Удаляем старые правила для этого порта
    delete_port_forward "$local_port" "$protocol"
    
    # Добавляем новые правила iptables
    iptables -t nat -A PREROUTING -p "$protocol" --dport "$local_port" \
        -j DNAT --to-destination "$remote_ip:$remote_port"
    
    iptables -A FORWARD -p "$protocol" -d "$remote_ip" --dport "$remote_port" \
        -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    
    iptables -A FORWARD -p "$protocol" -s "$remote_ip" --sport "$remote_port" \
        -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    iptables -A INPUT -p "$protocol" --dport "$local_port" -j ACCEPT
    
    # Включаем MASQUERADE если еще не включено
    local interface=$(ip route get 8.8.8.8 | awk '{print $5}')
    if ! iptables -t nat -C POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o "$interface" -j MASQUERADE
    fi
    
    # Сохраняем правило в конфиг
    save_rule "$local_port" "$protocol" "$remote_ip" "$remote_port"
    
    # Сохраняем правила iptables
    save_iptables_rules
    
    print_success "Проброс порта настроен"
    print_info "Подключение: ваш_сервер:$local_port -> $remote_ip:$remote_port ($protocol)"
}

delete_port_forward() {
    local local_port=$1
    local protocol=${2:-"tcp"}
    
    print_info "Удаление правил для порта $local_port/$protocol..."
    
    # Удаляем правила iptables
    iptables -t nat -D PREROUTING -p "$protocol" --dport "$local_port" -j DNAT 2>/dev/null || true
    iptables -D FORWARD -p "$protocol" --dport "$local_port" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p "$protocol" --dport "$local_port" -j ACCEPT 2>/dev/null || true
    
    # Удаляем из конфига
    delete_rule "$local_port" "$protocol"
    
    # Сохраняем правила iptables
    save_iptables_rules
    
    print_success "Правила для порта $local_port удалены"
}

add_cascade_forward() {
    local local_port=$1
    local remote_ip=$2
    local remote_port=$3
    local protocol=${4:-"tcp"}
    
    print_info "Настройка каскадного проброса..."
    print_info "Цепочка: клиент -> этот_сервер:$local_port -> $remote_ip:$remote_port"
    
    # Добавляем обычный проброс
    add_port_forward "$local_port" "$remote_ip" "$remote_port" "$protocol"
    
    # Дополнительные настройки для каскада
    optimize_cascade_settings
    
    # Сохраняем информацию о каскаде
    save_cascade_config "$local_port" "$remote_ip" "$remote_port" "$protocol"
    
    print_success "Каскадный проброс настроен"
}

optimize_cascade_settings() {
    print_info "Оптимизация настроек для каскада..."
    
    # Увеличиваем размеры буферов
    sysctl -w net.core.rmem_max=134217728 > /dev/null 2>&1
    sysctl -w net.core.wmem_max=134217728 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728" > /dev/null 2>&1
    
    # Увеличиваем лимиты соединений
    sysctl -w net.core.netdev_max_backlog=100000 > /dev/null 2>&1
    sysctl -w net.core.somaxconn=100000 > /dev/null 2>&1
    
    print_success "Настройки оптимизированы для каскада"
}

# ------------------------------------------------------------------------------
# УПРАВЛЕНИЕ КОНФИГУРАЦИЕЙ
# ------------------------------------------------------------------------------

save_rule() {
    local local_port=$1
    local protocol=$2
    local remote_ip=$3
    local remote_port=$4
    
    mkdir -p "$CONFIG_DIR"
    
    # Создаем файл конфигурации для правила
    local rule_file="$CONFIG_DIR/rule_${local_port}_${protocol}.conf"
    
    cat > "$rule_file" << EOF
# Правило проброса портов
LOCAL_PORT=$local_port
PROTOCOL=$protocol
REMOTE_IP=$remote_ip
REMOTE_PORT=$remote_port
CREATED=$(date +%Y-%m-%d\ %H:%M:%S)
EOF
    
    print_debug "Правило сохранено в $rule_file"
}

delete_rule() {
    local local_port=$1
    local protocol=$2
    
    local rule_file="$CONFIG_DIR/rule_${local_port}_${protocol}.conf"
    
    if [ -f "$rule_file" ]; then
        rm -f "$rule_file"
        print_debug "Файл правила удален: $rule_file"
    fi
}

save_cascade_config() {
    local local_port=$1
    local remote_ip=$2
    local remote_port=$3
    local protocol=$4
    
    local config_file="$CONFIG_DIR/cascade_${local_port}.conf"
    
    cat > "$config_file" << EOF
# Конфигурация каскадного проброса
LOCAL_PORT=$local_port
REMOTE_IP=$remote_ip
REMOTE_PORT=$remote_port
PROTOCOL=$protocol
TYPE=cascade
CREATED=$(date +%Y-%m-%d\ %H:%M:%S)
EOF
    
    print_debug "Конфиг каскада сохранен в $config_file"
}

save_iptables_rules() {
    print_info "Сохранение правил iptables..."
    
    # Для Debian/Ubuntu
    if [[ -f /etc/debian_version ]]; then
        iptables-save > /etc/iptables/rules.v4
        ip6tables-save > /etc/iptables/rules.v6
        
    # Для RHEL/CentOS
    elif [[ -f /etc/redhat-release ]]; then
        iptables-save > /etc/sysconfig/iptables
        service iptables save 2>/dev/null || true
    fi
    
    # Резервная копия
    mkdir -p "$BACKUP_DIR"
    iptables-save > "$BACKUP_DIR/iptables-$(date +%Y%m%d_%H%M%S).rules"
    
    print_success "Правила сохранены"
}

# ------------------------------------------------------------------------------
# УТИЛИТЫ ПРОСМОТРА И УПРАВЛЕНИЯ
# ------------------------------------------------------------------------------

list_rules() {
    print_info "Список активных правил проброса:"
    echo -e "${CYAN}ПОРТ\tПРОТОКОЛ\tНАПРАВЛЕНИЕ${NC}"
    echo -e "${CYAN}════\t══════════\t══════════════${NC}"
    
    # Показываем правила из iptables
    iptables -t nat -L PREROUTING -n | grep DNAT | while read -r line; do
        local port=$(echo "$line" | grep -oP 'dpt:\K\d+')
        local proto=$(echo "$line" | grep -oP 'multiport \K\w+')
        local dest=$(echo "$line" | grep -oP 'to:\K[\d\.:]+')
        
        if [ -n "$port" ]; then
            echo -e "$port\t$proto\t\t-> $dest"
        fi
    done
    
    # Показываем правила из конфигов
    if [ -d "$CONFIG_DIR" ]; then
        echo ""
        print_info "Сохраненные конфигурации:"
        for config in "$CONFIG_DIR"/*.conf; do
            if [ -f "$config" ]; then
                echo "  $(basename "$config")"
            fi
        done
    fi
}

show_rule_details() {
    local local_port=$1
    local protocol=${2:-"tcp"}
    
    local rule_file="$CONFIG_DIR/rule_${local_port}_${protocol}.conf"
    
    if [ ! -f "$rule_file" ]; then
        print_error "Правило для порта $local_port/$protocol не найдено"
        return 1
    fi
    
    print_info "Детали правила:"
    cat "$rule_file"
    
    # Показываем статистику iptables
    echo ""
    print_info "Статистика трафика:"
    iptables -L -n -v | grep "dpt:$local_port" || echo "  Нет статистики"
}

test_port_forward() {
    local local_port=$1
    local protocol=${2:-"tcp"}
    
    print_info "Тестирование проброса порта $local_port/$protocol..."
    
    # Проверяем, слушается ли порт
    if netstat -tuln | grep -q ":$local_port "; then
        print_success "Порт $local_port слушается"
    else
        print_error "Порт $local_port не слушается"
        return 1
    fi
    
    # Проверяем правило в iptables
    if iptables -t nat -L PREROUTING -n | grep -q "dpt:$local_port"; then
        print_success "Правило iptables существует"
    else
        print_error "Правило iptables не найдено"
        return 1
    fi
    
    # Пробуем подключиться локально
    if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$local_port" 2>/dev/null; then
        print_success "Локальное подключение работает"
    else
        print_warning "Не удалось подключиться локально"
    fi
    
    print_success "Тестирование завершено"
}

cleanup_old_rules() {
    print_info "Очистка старых правил..."
    
    # Удаляем все правила проброса
    iptables -t nat -F PREROUTING
    iptables -F FORWARD
    iptables -F INPUT
    
    # Оставляем только базовые правила
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # Очищаем конфиги
    rm -rf "$CONFIG_DIR"/*.conf 2>/dev/null
    
    # Сохраняем чистые правила
    save_iptables_rules
    
    print_success "Все правила очищены"
}

# ------------------------------------------------------------------------------
# ГЛАВНОЕ МЕНЮ
# ------------------------------------------------------------------------------

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               МОДУЛЬ ПРОБРОСА ПОРТОВ (IPTABLES)              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${GREEN}[1]${NC} Добавить проброс порта"
    echo -e "${GREEN}[2]${NC} Добавить каскадный проброс"
    echo -e "${GREEN}[3]${NC} Удалить проброс порта"
    echo -e "${GREEN}[4]${NC} Список активных правил"
    echo -e "${GREEN}[5]${NC} Тестирование проброса"
    echo -e "${GREEN}[6]${NC} Очистить все правила"
    echo -e "${GREEN}[7]${NC} Сохранить правила"
    echo -e "${YELLOW}[8]${NC} Настройка системы"
    echo -e "${WHITE}[0]${NC} Выход\n"
    
    read -p "Выберите действие (0-8): " choice
    
    case $choice in
        1)
            read -p "Локальный порт: " local_port
            read -p "Удаленный IP: " remote_ip
            read -p "Удаленный порт: " remote_port
            read -p "Протокол (tcp/udp) [tcp]: " protocol
            protocol=${protocol:-"tcp"}
            
            add_port_forward "$local_port" "$remote_ip" "$remote_port" "$protocol"
            ;;
            
        2)
            read -p "Локальный порт (входной): " local_port
            read -p "Удаленный сервер IP: " remote_ip
            read -p "Удаленный порт: " remote_port
            read -p "Протокол (tcp/udp) [tcp]: " protocol
            protocol=${protocol:-"tcp"}
            
            add_cascade_forward "$local_port" "$remote_ip" "$remote_port" "$protocol"
            ;;
            
        3)
            read -p "Локальный порт для удаления: " local_port
            read -p "Протокол (tcp/udp) [tcp]: " protocol
            protocol=${protocol:-"tcp"}
            
            delete_port_forward "$local_port" "$protocol"
            ;;
            
        4)
            list_rules
            ;;
            
        5)
            read -p "Порт для тестирования: " local_port
            read -p "Протокол (tcp/udp) [tcp]: " protocol
            protocol=${protocol:-"tcp"}
            
            test_port_forward "$local_port" "$protocol"
            ;;
            
        6)
            read -p "Вы уверены? Все правила будут удалены! (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                cleanup_old_rules
            fi
            ;;
            
        7)
            save_iptables_rules
            ;;
            
        8)
            enable_ip_forwarding
            setup_persistent_rules
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
    
    # Проверяем и настраиваем iptables
    check_iptables
    enable_ip_forwarding
    setup_persistent_rules
    
    # Создаем директории
    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
    
    # Показываем меню
    show_menu
}

# ------------------------------------------------------------------------------
# ЗАПУСК С АРГУМЕНТАМИ
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [команда]"
        echo ""
        echo "Команды:"
        echo "  --add <лок_порт> <удал_ip> <удал_порт> [протокол]  Добавить проброс"
        echo "  --cascade <лок_порт> <удал_ip> <удал_порт>         Каскадный проброс"
        echo "  --delete <порт> [протокол]                         Удалить проброс"
        echo "  --list                                             Список правил"
        echo "  --test <порт> [протокол]                          Тестировать проброс"
        echo "  --cleanup                                          Очистить все правила"
        echo "  --save                                            Сохранить правила"
        echo "  --menu                                            Интерактивное меню"
        echo "  --help                                            Показать справку"
        ;;
    
    "--add")
        if [ $# -lt 4 ]; then
            print_error "Используйте: $0 --add <лок_порт> <удал_ip> <удал_порт> [протокол]"
            exit 1
        fi
        add_port_forward "$2" "$3" "$4" "${5:-tcp}"
        ;;
    
    "--cascade")
        if [ $# -lt 4 ]; then
            print_error "Используйте: $0 --cascade <лок_порт> <удал_ip> <удал_порт>"
            exit 1
        fi
        add_cascade_forward "$2" "$3" "$4" "${5:-tcp}"
        ;;
    
    "--delete")
        if [ $# -lt 2 ]; then
            print_error "Используйте: $0 --delete <порт> [протокол]"
            exit 1
        fi
        delete_port_forward "$2" "${3:-tcp}"
        ;;
    
    "--list")
        list_rules
        ;;
    
    "--test")
        if [ $# -lt 2 ]; then
            print_error "Используйте: $0 --test <порт> [протокол]"
            exit 1
        fi
        test_port_forward "$2" "${3:-tcp}"
        ;;
    
    "--cleanup")
        read -p "Очистить все правила? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            cleanup_old_rules
        fi
        ;;
    
    "--save")
        save_iptables_rules
        ;;
    
    "--menu"|"")
        main
        ;;
    
    *)
        print_error "Неизвестная команда: $1"
        echo "Используйте: $0 --help"
        exit 1
        ;;
esac