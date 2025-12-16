#!/bin/bash
# modules/clients/wireguard.sh - Генерация WireGuard клиентских конфигов

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly WG_DIR="/etc/wireguard"
readonly CLIENTS_DIR="$WG_DIR/clients"
readonly CONFIG_FILE="$WG_DIR/wg0.conf"
readonly TEMPLATES_DIR="/opt/cascade-vpn/templates/wireguard"

# ------------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ------------------------------------------------------------------------------

check_wireguard() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "WireGuard не настроен. Сначала запустите установку WireGuard.")
        return 1
    fi
    
    if [ ! -f "$WG_DIR/server-public.key" ]; then
        print_error "Ключи WireGuard не найдены.")
        return 1
    fi
    
    return 0
}

get_server_info() {
    local server_ip=$(curl -s ifconfig.me)
    local server_port=$(grep "ListenPort" "$CONFIG_FILE" | awk '{print $3}')
    local server_public_key=$(cat "$WG_DIR/server-public.key" 2>/dev/null)
    local subnet=$(grep "Address" "$CONFIG_FILE" | head -1 | awk '{print $3}' | cut -d'/' -f1)
    
    echo "$server_ip $server_port $server_public_key $subnet"
}

generate_client_keys() {
    local client_name=$1
    
    print_info "Генерация ключей для клиента $client_name...")
    
    # Генерируем ключи
    wg genkey | tee "$CLIENTS_DIR/$client_name-private.key" | wg pubkey > "$CLIENTS_DIR/$client_name-public.key"
    local client_private_key=$(cat "$CLIENTS_DIR/$client_name-private.key")
    local client_public_key=$(cat "$CLIENTS_DIR/$client_name-public.key")
    
    # Генерируем PSK (необязательно, но рекомендуется)
    wg genpsk > "$CLIENTS_DIR/$client_name-psk.key" 2>/dev/null || true
    local client_psk=$(cat "$CLIENTS_DIR/$client_name-psk.key" 2>/dev/null || echo "")
    
    echo "$client_private_key $client_public_key $client_psk"
}

allocate_client_ip() {
    local client_name=$1
    local subnet=$2
    
    print_info "Выделение IP адреса для клиента...")
    
    # Получаем базовый IP подсети (например, 10.8.0.0/24 -> 10.8.0.)
    local base_ip=$(echo "$subnet" | sed 's/\.[0-9]*\/.*$/.0/')
    local network_prefix=$(echo "$subnet" | cut -d'/' -f2)
    
    # Находим использованные IP адреса
    local used_ips=($(grep "AllowedIPs" "$CONFIG_FILE" | awk '{print $3}' | cut -d'/' -f1))
    
    # Начинаем с .2 (сервер обычно .1)
    local client_number=2
    
    # Ищем свободный IP
    while [[ " ${used_ips[@]} " =~ " $(echo $base_ip | sed "s/\.0$/.$client_number/") " ]]; do
        ((client_number++))
        
        # Проверяем, не вышли ли за пределы подсети
        if [ $client_number -ge 254 ]; then
            print_error "Нет свободных IP адресов в подсети!")
            exit 1
        fi
    done
    
    local client_ip=$(echo $base_ip | sed "s/\.0$/.$client_number/")
    
    print_success "Выделен IP: $client_ip/$network_prefix")
    echo "$client_ip/$network_prefix"
}

add_client_to_server() {
    local client_name=$1
    local client_public_key=$2
    local client_ip=$3
    local client_psk=${4:-""}
    
    print_info "Добавление клиента $client_name в конфиг сервера...")
    
    # Добавляем Peer в конфиг сервера
    local peer_config="\n[Peer]\n# $client_name\nPublicKey = $client_public_key\nAllowedIPs = $client_ip"
    
    if [ -n "$client_psk" ]; then
        peer_config="$peer_config\nPresharedKey = $client_psk"
    fi
    
    # Добавляем PersistentKeepalive для лучшей связи
    peer_config="$peer_config\nPersistentKeepalive = 25"
    
    # Добавляем в конфиг
    echo -e "$peer_config" >> "$CONFIG_FILE"
    
    # Перезагружаем конфигурацию WireGuard
    wg syncconf wg0 <(wg-quick strip wg0)
    
    print_success "Клиент добавлен на сервер")
}

# ------------------------------------------------------------------------------
# ГЕНЕРАЦИЯ КОНФИГОВ
# ------------------------------------------------------------------------------

generate_wireguard_config() {
    local client_name=$1
    local server_ip=$2
    local server_port=$3
    local server_public_key=$4
    local client_private_key=$5
    local client_ip=$6
    local client_psk=${7:-""}
    local dns=${8:-"1.1.1.1,8.8.8.8"}
    local mtu=${9:-1420}
    
    print_info "Генерация конфигурации WireGuard для $client_name...")
    
    # Создаем конфиг клиента
    local config_content="[Interface]\n"
    config_content="${config_content}PrivateKey = $client_private_key\n"
    config_content="${config_content}Address = $client_ip\n"
    config_content="${config_content}DNS = $dns\n"
    config_content="${config_content}MTU = $mtu\n\n"
    config_content="${config_content}[Peer]\n"
    config_content="${config_content}PublicKey = $server_public_key\n"
    config_content="${config_content}Endpoint = $server_ip:$server_port\n"
    config_content="${config_content}AllowedIPs = 0.0.0.0/0\n"
    config_content="${config_content}PersistentKeepalive = 25\n"
    
    if [ -n "$client_psk" ]; then
        config_content="${config_content}PresharedKey = $client_psk\n"
    fi
    
    # Сохраняем конфиг
    local config_file="$CLIENTS_DIR/$client_name.conf"
    echo -e "$config_content" > "$config_file"
    
    print_success "Конфиг создан: $config_file")
    echo "$config_file"
}

generate_qr_code() {
    local config_file=$1
    
    if ! command -v qrencode > /dev/null; then
        print_warning "qrencode не установлен. Установите: apt-get install qrencode")
        return 1
    fi
    
    local qr_file="${config_file%.conf}.png"
    local qr_text_file="${config_file%.conf}-qr.txt"
    
    print_info "Генерация QR-кода...")
    
    # Генерируем QR-код
    qrencode -o "$qr_file" -t PNG < "$config_file"
    
    # Также создаем текстовый QR-код для терминала
    qrencode -t UTF8 < "$config_file" > "$qr_text_file"
    
    # Показываем QR-код в терминале
    echo ""
    print_info "QR-код для импорта:")
    qrencode -t ANSIUTF8 < "$config_file"
    echo ""
    
    print_success "QR-код создан: $qr_file")
    echo "$qr_file"
}

generate_mobile_config() {
    local client_name=$1
    local config_file=$2
    
    print_info "Генерация мобильной конфигурации...")
    
    local mobile_config="${config_file%.conf}.mobile.conf"
    
    # Упрощаем конфиг для мобильных клиентов
    cat "$config_file" | sed 's/MTU = .*/MTU = 1280/' > "$mobile_config"
    
    # Добавляем комментарий
    echo "# Mobile optimized config" >> "$mobile_config"
    echo "# Generated: $(date)" >> "$mobile_config"
    
    print_success "Мобильный конфиг создан: $mobile_config")
    echo "$mobile_config"
}

# ------------------------------------------------------------------------------
# УПРАВЛЕНИЕ КЛИЕНТАМИ
# ------------------------------------------------------------------------------

list_clients() {
    print_info "Список WireGuard клиентов:")
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    
    if [ ! -d "$CLIENTS_DIR" ] || [ -z "$(ls -A "$CLIENTS_DIR"/*.conf 2>/dev/null)" ]; then
        echo "  Клиенты не найдены"
        return
    fi
    
    for config in "$CLIENTS_DIR"/*.conf; do
        local client_name=$(basename "$config" .conf)
        local client_ip=$(grep "Address" "$config" | awk '{print $3}')
        local creation_time=$(stat -c %y "$config" 2>/dev/null | cut -d' ' -f1)
        
        echo -e "${GREEN}○${NC} $client_name"
        echo "  IP: $client_ip"
        echo "  Создан: $creation_time"
        echo "  Конфиг: $(basename "$config")"
        
        # Проверяем наличие QR-кода
        if [ -f "${config%.conf}.png" ]; then
            echo "  QR-код: ✓"
        fi
        
        echo ""
    done
}

revoke_client() {
    local client_name=$1
    
    print_info "Отзыв клиента $client_name...")
    
    # Проверяем существование клиента
    if [ ! -f "$CLIENTS_DIR/$client_name.conf" ]; then
        print_error "Клиент $client_name не найден")
        return 1
    fi
    
    # Получаем публичный ключ клиента
    local client_public_key=$(cat "$CLIENTS_DIR/$client_name-public.key" 2>/dev/null || echo "")
    
    if [ -n "$client_public_key" ]; then
        # Удаляем Peer из конфига сервера
        sed -i "/# $client_name/,/^$/d" "$CONFIG_FILE"
        
        # Перезагружаем WireGuard
        wg syncconf wg0 <(wg-quick strip wg0)
        
        print_success "Клиент удален из сервера")
    fi
    
    # Архивируем файлы клиента
    local backup_dir="$CLIENTS_DIR/revoked"
    mkdir -p "$backup_dir"
    
    mv "$CLIENTS_DIR/$client_name"* "$backup_dir/" 2>/dev/null || true
    
    print_success "Клиент $client_name отозван")
    print_info "Файлы перемещены в: $backup_dir/")
}

rotate_client_keys() {
    local client_name=$1
    
    print_info "Ротация ключей для клиента $client_name...")
    
    # Генерируем новые ключи
    local keys=$(generate_client_keys "$client_name-new")
    local new_private_key=$(echo $keys | awk '{print $1}')
    local new_public_key=$(echo $keys | awk '{print $2}')
    local new_psk=$(echo $keys | awk '{print $3}')
    
    # Получаем старый IP клиента
    local old_config="$CLIENTS_DIR/$client_name.conf"
    local client_ip=$(grep "Address" "$old_config" | awk '{print $3}')
    
    # Получаем данные сервера
    local server_info=$(get_server_info)
    local server_ip=$(echo $server_info | awk '{print $1}')
    local server_port=$(echo $server_info | awk '{print $2}')
    local server_public_key=$(echo $server_info | awk '{print $3}')
    
    # Создаем новый конфиг
    generate_wireguard_config \
        "$client_name-new" \
        "$server_ip" \
        "$server_port" \
        "$server_public_key" \
        "$new_private_key" \
        "$client_ip" \
        "$new_psk"
    
    # Обновляем на сервере
    add_client_to_server "$client_name-new" "$new_public_key" "$client_ip" "$new_psk"
    
    # Архивируем старые ключи
    local backup_dir="$CLIENTS_DIR/rotated"
    mkdir -p "$backup_dir"
    mv "$CLIENTS_DIR/$client_name"* "$backup_dir/" 2>/dev/null || true
    
    # Переименовываем новые файлы
    mv "$CLIENTS_DIR/$client_name-new"* "$CLIENTS_DIR/$client_name"*
    
    print_success "Ключи клиента $client_name обновлены")
    print_info "Старые ключи архивированы в: $backup_dir/")
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

create_client() {
    local client_name=$1
    local dns=${2:-"1.1.1.1,8.8.8.8"}
    local mtu=${3:-1420}
    
    print_info "Создание нового WireGuard клиента: $client_name")
    
    # Проверяем WireGuard
    if ! check_wireguard; then
        return 1
    fi
    
    # Проверяем, что клиент не существует
    if [ -f "$CLIENTS_DIR/$client_name.conf" ]; then
        print_error "Клиент $client_name уже существует!")
        read -p "Перезаписать? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Создаем директории
    mkdir -p "$CLIENTS_DIR"
    
    # Получаем информацию о сервере
    local server_info=$(get_server_info)
    local server_ip=$(echo $server_info | awk '{print $1}')
    local server_port=$(echo $server_info | awk '{print $2}')
    local server_public_key=$(echo $server_info | awk '{print $3}')
    local subnet=$(echo $server_info | awk '{print $4}')
    
    # Генерируем ключи клиента
    local keys=$(generate_client_keys "$client_name")
    local client_private_key=$(echo $keys | awk '{print $1}')
    local client_public_key=$(echo $keys | awk '{print $2}')
    local client_psk=$(echo $keys | awk '{print $3}')
    
    # Выделяем IP адрес
    local client_ip=$(allocate_client_ip "$client_name" "$subnet")
    
    # Добавляем клиента на сервер
    add_client_to_server "$client_name" "$client_public_key" "$client_ip" "$client_psk"
    
    # Генерируем конфиг
    local config_file=$(generate_wireguard_config \
        "$client_name" \
        "$server_ip" \
        "$server_port" \
        "$server_public_key" \
        "$client_private_key" \
        "$client_ip" \
        "$client_psk" \
        "$dns" \
        "$mtu")
    
    # Генерируем QR-код
    generate_qr_code "$config_file"
    
    # Генерируем мобильную версию
    generate_mobile_config "$client_name" "$config_file"
    
    # Показываем информацию
    show_client_info "$client_name" "$config_file" "$client_ip"
    
    print_success "Клиент $client_name успешно создан!")
}

show_client_info() {
    local client_name=$1
    local config_file=$2
    local client_ip=$3
    
    local server_ip=$(curl -s ifconfig.me)
    local config_content=$(cat "$config_file")
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}          КЛИЕНТ WIREGUARD СОЗДАН!                             ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}▸ ИНФОРМАЦИЯ О КЛИЕНТЕ:${NC}"
    echo -e "  Имя:       ${YELLOW}$client_name${NC}"
    echo -e "  IP адрес:  ${YELLOW}$client_ip${NC}"
    echo -e "  Сервер:    ${YELLOW}$server_ip${NC}"
    
    echo -e "\n${CYAN}▸ ФАЙЛЫ:${NC}"
    echo -e "  Конфиг:    ${WHITE}$config_file${NC}"
    echo -e "  QR-код:    ${WHITE}${config_file%.conf}.png${NC}"
    echo -e "  Мобильный: ${WHITE}${config_file%.conf}.mobile.conf${NC}"
    
    echo -e "\n${CYAN}▸ ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "  1. Скопируйте файл конфигурации на устройство"
    echo "  2. Или отсканируйте QR-код в приложении WireGuard"
    echo "  3. Импортируйте конфиг в WireGuard клиент"
    
    echo -e "\n${CYAN}▸ ПРОВЕРКА:${NC}"
    echo "  После подключения проверьте:"
    echo "  ping $server_ip"
    echo "  curl ifconfig.me"
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
}

# ------------------------------------------------------------------------------
# ГЛАВНОЕ МЕНЮ
# ------------------------------------------------------------------------------

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ГЕНЕРАТОР КЛИЕНТОВ WIREGUARD                        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${GREEN}[1]${NC} Создать нового клиента"
    echo -e "${GREEN}[2]${NC} Список всех клиентов"
    echo -e "${GREEN}[3]${NC} Сгенерировать QR-код для клиента"
    echo -e "${GREEN}[4]${NC} Отозвать клиента"
    echo -e "${GREEN}[5]${NC} Ротация ключей клиента"
    echo -e "${GREEN}[6]${NC} Экспорт всех клиентов"
    echo -e "${WHITE}[0]${NC} Выход\n"
    
    read -p "Выберите действие (0-6): " choice
    
    case $choice in
        1)
            read -p "Имя клиента: " client_name
            read -p "DNS серверы [1.1.1.1,8.8.8.8]: " dns
            dns=${dns:-"1.1.1.1,8.8.8.8"}
            
            create_client "$client_name" "$dns"
            ;;
            
        2)
            list_clients
            ;;
            
        3)
            read -p "Имя клиента: " client_name
            if [ -f "$CLIENTS_DIR/$client_name.conf" ]; then
                generate_qr_code "$CLIENTS_DIR/$client_name.conf"
            else
                print_error "Клиент $client_name не найден")
            fi
            ;;
            
        4)
            read -p "Имя клиента для отзыва: " client_name
            revoke_client "$client_name"
            ;;
            
        5)
            read -p "Имя клиента для ротации ключей: " client_name
            rotate_client_keys "$client_name"
            ;;
            
        6)
            print_info "Экспорт всех клиентов...")
            tar -czf "/tmp/wireguard-clients-$(date +%Y%m%d).tar.gz" -C "$CLIENTS_DIR" .
            print_success "Клиенты экспортированы в: /tmp/wireguard-clients-$(date +%Y%m%d).tar.gz")
            ;;
            
        0)
            echo "Выход."
            exit 0
            ;;
            
        *)
            print_error "Неверный выбор")
            ;;
    esac
    
    echo ""
    read -p "Нажмите Enter для продолжения..." -n 1
    show_menu
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

main() {
    print_info "Генератор WireGuard клиентов")
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root")
        exit 1
    fi
    
    # Создаем директории
    mkdir -p "$CLIENTS_DIR"
    
    # Показываем меню
    show_menu
}

# ------------------------------------------------------------------------------
# КОМАНДНАЯ СТРОКА
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [команда]"
        echo ""
        echo "Команды:"
        echo "  --create <имя> [dns] [mtu]   Создать клиента"
        echo "  --list                       Список клиентов"
        echo "  --qr <имя>                  Генерация QR-кода"
        echo "  --revoke <имя>              Отозвать клиента"
        echo "  --rotate <имя>              Ротация ключей"
        echo "  --export                    Экспорт всех клиентов"
        echo "  --menu                      Интерактивное меню"
        echo "  --help                      Показать справку"
        ;;
    
    "--create")
        if [ -z "$2" ]; then
            print_error "Укажите имя клиента: $0 --create имя")
            exit 1
        fi
        create_client "$2" "${3:-}" "${4:-}"
        ;;
    
    "--list")
        list_clients
        ;;
    
    "--qr")
        if [ -z "$2" ]; then
            print_error "Укажите имя клиента: $0 --qr имя")
            exit 1
        fi
        generate_qr_code "$CLIENTS_DIR/$2.conf"
        ;;
    
    "--revoke")
        if [ -z "$2" ]; then
            print_error "Укажите имя клиента: $0 --revoke имя")
            exit 1
        fi
        revoke_client "$2"
        ;;
    
    "--rotate")
        if [ -z "$2" ]; then
            print_error "Укажите имя клиента: $0 --rotate имя")
            exit 1
        fi
        rotate_client_keys "$2"
        ;;
    
    "--export")
        tar -czf "/tmp/wireguard-clients-$(date +%Y%m%d).tar.gz" -C "$CLIENTS_DIR" .
        print_success "Экспортировано в: /tmp/wireguard-clients-$(date +%Y%m%d).tar.gz")
        ;;
    
    "--menu"|"")
        main
        ;;
    
    *)
        print_error "Неизвестная команда: $1")
        echo "Используйте: $0 --help"
        exit 1
        ;;
esac