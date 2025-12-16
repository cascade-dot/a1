#!/bin/bash
# services/3x-ui/install.sh - Установка 3x-ui панели

set -euo pipefail

UI3X_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UI3X_SCRIPT_DIR/../../utils/colors.sh"
source "$UI3X_SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly INSTALL_DIR="/opt/3x-ui"
readonly CONFIG_DIR="/etc/3x-ui"
readonly BACKUP_DIR="/var/backups/3x-ui"
readonly DOCKER_IMAGE="sagernet/x-ui:latest"
readonly PANEL_PORT=8443
readonly XRAY_PORT=443

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

check_docker() {
    if ! command -v docker > /dev/null; then
        print_error "Docker не установлен"
        exit 1
    fi
}

generate_credentials() {
    print_info "Генерация учетных данных..."
    
    mkdir -p "$CONFIG_DIR"
    
    local username="admin"
    local password=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-12)
    
    # Сохраняем пароль
    echo "$password" > "$CONFIG_DIR/admin-password.txt"
    chmod 600 "$CONFIG_DIR/admin-password.txt"
    
    print_success "Учетные данные сгенерированы"
    print_info "Пароль администратора: $password"
}

setup_directories() {
    print_info "Создание директорий..."
    
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "/var/log/x-ui"
    
    # Права
    chmod 750 "$CONFIG_DIR" "$BACKUP_DIR"
    
    print_success "Директории созданы"
}

create_docker_compose() {
    print_info "Создание Docker Compose конфигурации..."
    
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  x-ui:
    image: $DOCKER_IMAGE
    container_name: 3x-ui
    restart: unless-stopped
    network_mode: host
    volumes:
      - $CONFIG_DIR:/etc/x-ui
      - /var/log/x-ui:/var/log/x-ui
      - $BACKUP_DIR:/backups
    environment:
      - XRAY_VMESS_AEAD_FORCED=false
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    print_success "Docker Compose файл создан"
}

setup_firewall() {
    print_info "Настройка фаервола..."
    
    # Открываем порты
    if command -v ufw > /dev/null; then
        ufw allow $PANEL_PORT/tcp comment "3x-ui Panel"
        ufw allow $XRAY_PORT/tcp comment "Xray Core"
        ufw allow $XRAY_PORT/udp comment "Xray Core UDP"
        ufw allow 80/tcp comment "HTTP for ACME"
        ufw reload
    elif command -v firewall-cmd > /dev/null; then
        firewall-cmd --permanent --add-port=$PANEL_PORT/tcp
        firewall-cmd --permanent --add-port=$XRAY_PORT/tcp
        firewall-cmd --permanent --add-port=$XRAY_PORT/udp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --reload
    fi
    
    print_success "Фаервол настроен"
}

start_service() {
    print_info "Запуск 3x-ui..."
    
    cd "$INSTALL_DIR"
    docker-compose up -d
    
    # Ждем запуска
    sleep 10
    
    if docker ps | grep -q "3x-ui"; then
        print_success "3x-ui запущен"
    else
        print_error "Не удалось запустить 3x-ui"
        docker-compose logs
        exit 1
    fi
}

create_systemd_service() {
    print_info "Создание systemd службы..."
    
    cat > /etc/systemd/system/3x-ui.service << EOF
[Unit]
Description=3x-ui Xray Panel
Requires=docker.service
After=docker.service network.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable 3x-ui.service
    
    print_success "Systemd служба создана"
}

setup_backup() {
    print_info "Настройка автоматических бэкапов..."
    
    cat > /usr/local/bin/3x-ui-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/3x-ui"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup-$DATE.tar.gz"

tar -czf "$BACKUP_FILE" /etc/3x-ui /var/log/x-ui 2>/dev/null

# Удаляем старые бэкапы
find "$BACKUP_DIR" -name "backup-*.tar.gz" -mtime +7 -delete

echo "Бэкап создан: $BACKUP_FILE"
EOF
    
    chmod +x /usr/local/bin/3x-ui-backup.sh
    
    # Cron для ежедневных бэкапов
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/3x-ui-backup.sh > /dev/null 2>&1") | crontab -
    
    print_success "Автоматические бэкапы настроены"
}

show_connection_info() {
    local public_ip=$(curl -s ifconfig.me)
    local password=$(cat "$CONFIG_DIR/admin-password.txt" 2>/dev/null || echo "не найден")
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}               3X-UI УСТАНОВЛЕН УСПЕШНО!                       ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}▸ ВЕБ-ПАНЕЛЬ УПРАВЛЕНИЯ:${NC}"
    echo -e "  URL:      ${YELLOW}https://$public_ip:$PANEL_PORT${NC}"
    echo -e "  Логин:    ${YELLOW}admin${NC}"
    echo -e "  Пароль:   ${YELLOW}$password${NC}"
    
    echo -e "\n${CYAN}▸ ПОРТЫ ДЛЯ КЛИЕНТОВ:${NC}"
    echo -e "  Xray Core: ${WHITE}$XRAY_PORT${NC} (TCP/UDP)"
    echo -e "  HTTP:      ${WHITE}80${NC} (для ACME)"
    
    echo -e "\n${CYAN}▸ КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
    echo -e "  Статус:    ${WHITE}systemctl status 3x-ui${NC}"
    echo -e "  Логи:      ${WHITE}docker logs 3x-ui${NC}"
    echo -e "  Бэкап:     ${WHITE}/usr/local/bin/3x-ui-backup.sh${NC}"
    
    echo -e "\n${CYAN}▸ ПАПКИ:${NC}"
    echo -e "  Конфиги:   ${WHITE}$CONFIG_DIR${NC}"
    echo -e "  Логи:      ${WHITE}/var/log/x-ui${NC}"
    echo -e "  Бэкапы:    ${WHITE}$BACKUP_DIR${NC}"
    
    echo -e "\n${YELLOW}⚠️  ВАЖНО:${NC}"
    echo "  1. Смените пароль после первого входа!"
    echo "  2. Настройте SSL сертификат в панели"
    echo "  3. Создайте пользователей для подключения"
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    print_info "Начало установки 3x-ui..."
    
    # Проверки
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root"
        exit 1
    fi
    
    check_docker
    
    # Установка
    generate_credentials
    setup_directories
    create_docker_compose
    setup_firewall
    start_service
    create_systemd_service
    setup_backup
    
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
        echo "  --install     Установить 3x-ui"
        echo "  --start       Запустить службу"
        echo "  --stop        Остановить службу"
        echo "  --status      Показать статус"
        echo "  --update      Обновить 3x-ui"
        echo "  --uninstall   Удалить 3x-ui"
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
        if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
            cd "$INSTALL_DIR" && docker-compose ps
        else
            print_error "3x-ui не установлен"
        fi
        ;;
    "--update")
        cd "$INSTALL_DIR" && docker-compose pull && docker-compose up -d
        print_success "3x-ui обновлен"
        ;;
    "--uninstall")
        read -p "Удалить 3x-ui и все данные? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            cd "$INSTALL_DIR" 2>/dev/null && docker-compose down -v
            systemctl disable 3x-ui.service 2>/dev/null
            rm -f /etc/systemd/system/3x-ui.service
            rm -rf "$INSTALL_DIR" "$CONFIG_DIR" "$BACKUP_DIR"
            rm -f /usr/local/bin/3x-ui-backup.sh
            print_success "3x-ui удален"
        fi
        ;;
    *)
        main
        ;;
esac