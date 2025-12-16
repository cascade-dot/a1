#!/bin/bash
# services/wireguard/wg-easy.sh - WireGuard с веб-панелью wg-easy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly INSTALL_DIR="/opt/wg-easy"
readonly COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
readonly DEFAULT_PORT=51820
readonly WEB_PORT=51821

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

check_docker() {
    if ! command -v docker > /dev/null; then
        print_error "Docker не установлен. Установите Docker сначала."
        exit 1
    fi
    
    if ! command -v docker-compose > /dev/null; then
        print_error "Docker Compose не установлен. Установите Docker Compose."
        exit 1
    fi
}

setup_environment() {
    print_info "Настройка окружения..."
    
    mkdir -p "$INSTALL_DIR"
    
    # Получаем публичный IP
    local public_ip=$(curl -s ifconfig.me)
    
    # Генерируем пароль для панели
    local admin_password=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-12)
    
    # Создаем docker-compose файл
    cat > "$COMPOSE_FILE" << EOF
version: '3.8'
services:
  wg-easy:
    environment:
      # Внешний IP/DOMAIN сервера
      WG_HOST=$public_ip
      
      # Пароль для входа в веб-панель
      PASSWORD=$admin_password
      
      # Порт WireGuard
      WG_PORT=$DEFAULT_PORT
      
      # Внутренняя подсеть для клиентов
      WG_DEFAULT_ADDRESS=10.8.0.x
      
      # DNS для клиентов
      WG_DEFAULT_DNS_SERVER=1.1.1.1
      
      # Разрешить все IP
      WG_ALLOWED_IPS=0.0.0.0/0
      
      # Персистентные keepalive
      WG_PERSISTENT_KEEPALIVE=25
      
    image: weejewel/wg-easy
    container_name: wg-easy
    volumes:
      - $INSTALL_DIR/wireguard:/etc/wireguard
    ports:
      - "$DEFAULT_PORT:51820/udp"
      - "$WEB_PORT:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
EOF
    
    # Создаем .env файл с паролем
    cat > "$INSTALL_DIR/.env" << EOF
WG_HOST=$public_ip
WG_PASSWORD=$admin_password
WG_PORT=$DEFAULT_PORT
WEB_PORT=$WEB_PORT
EOF
    
    chmod 600 "$INSTALL_DIR/.env"
    
    print_success "Окружение настроено"
    print_info "Пароль администратора: $admin_password"
}

setup_firewall() {
    print_info "Настройка фаервола..."
    
    # Открываем порты
    if command -v ufw > /dev/null; then
        ufw allow $DEFAULT_PORT/udp comment "WireGuard VPN"
        ufw allow $WEB_PORT/tcp comment "WG-Easy Web Panel"
        ufw reload
    elif command -v firewall-cmd > /dev/null; then
        firewall-cmd --permanent --add-port=$DEFAULT_PORT/udp
        firewall-cmd --permanent --add-port=$WEB_PORT/tcp
        firewall-cmd --reload
    fi
    
    print_success "Фаервол настроен"
}

start_service() {
    print_info "Запуск wg-easy..."
    
    cd "$INSTALL_DIR"
    docker-compose up -d
    
    # Ждем запуска
    sleep 5
    
    if docker ps | grep -q "wg-easy"; then
        print_success "wg-easy запущен"
    else
        print_error "Не удалось запустить wg-easy"
        docker-compose logs
        exit 1
    fi
}

create_systemd_service() {
    print_info "Создание systemd службы..."
    
    cat > /etc/systemd/system/wg-easy.service << EOF
[Unit]
Description=WG-Easy WireGuard Web UI
Requires=docker.service
After=docker.service network.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable wg-easy.service
    
    print_success "Systemd служба создана"
}

show_connection_info() {
    local public_ip=$(curl -s ifconfig.me)
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}               WG-EASY УСТАНОВЛЕН УСПЕШНО!                     ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}▸ ВЕБ-ПАНЕЛЬ УПРАВЛЕНИЯ:${NC}"
    echo -e "  URL:      ${YELLOW}http://$public_ip:$WEB_PORT${NC}"
    echo -e "  Пароль:   ${YELLOW}$(grep WG_PASSWORD "$INSTALL_DIR/.env" | cut -d= -f2)${NC}"
    
    echo -e "\n${CYAN}▸ ПОДКЛЮЧЕНИЕ WIREGUARD:${NC}"
    echo -e "  Сервер:   ${WHITE}$public_ip${NC}"
    echo -e "  Порт:     ${WHITE}$DEFAULT_PORT${NC}"
    echo -e "  Протокол: ${WHITE}UDP${NC}"
    
    echo -e "\n${CYAN}▸ КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
    echo -e "  Статус:   ${WHITE}systemctl status wg-easy${NC}"
    echo -e "  Логи:     ${WHITE}docker logs wg-easy${NC}"
    echo -e "  Перезапуск: ${WHITE}docker-compose -f $COMPOSE_FILE restart${NC}"
    
    echo -e "\n${CYAN}▸ ПАПКИ:${NC}"
    echo -e "  Конфиги:  ${WHITE}$INSTALL_DIR/wireguard${NC}"
    echo -e "  Логи:     ${WHITE}$INSTALL_DIR/logs${NC}"
    
    echo -e "\n${YELLOW}⚠️  СОВЕТЫ:${NC}"
    echo "  1. Зайдите в веб-панель и смените пароль"
    echo "  2. Создайте первого клиента через веб-интерфейс"
    echo "  3. Сканируйте QR-код с телефона"
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    print_info "Начало установки wg-easy..."
    
    # Проверки
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root"
        exit 1
    fi
    
    check_docker
    
    # Установка
    setup_environment
    setup_firewall
    start_service
    create_systemd_service
    
    # Информация
    show_connection_info
    
    print_success "Установка завершена!"
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [опции]"
        echo ""
        echo "Опции:"
        echo "  --install     Установить wg-easy"
        echo "  --start       Запустить службу"
        echo "  --stop        Остановить службу"
        echo "  --status      Показать статус"
        echo "  --uninstall   Удалить wg-easy"
        echo "  --help        Показать справку"
        ;;
    "--install")
        main
        ;;
    "--start")
        cd "$INSTALL_DIR" && docker-compose start
        ;;
    "--stop")
        cd "$INSTALL_DIR" && docker-compose stop
        ;;
    "--status")
        if [ -f "$COMPOSE_FILE" ]; then
            cd "$INSTALL_DIR" && docker-compose ps
        else
            print_error "wg-easy не установлен"
        fi
        ;;
    "--uninstall")
        read -p "Удалить wg-easy и все данные? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            cd "$INSTALL_DIR" 2>/dev/null && docker-compose down -v
            systemctl disable wg-easy.service 2>/dev/null
            rm -f /etc/systemd/system/wg-easy.service
            rm -rf "$INSTALL_DIR"
            print_success "wg-easy удален"
        fi
        ;;
    *)
        main
        ;;
esac