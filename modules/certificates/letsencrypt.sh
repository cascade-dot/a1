#!/bin/bash
# modules/certificates/letsencrypt.sh - Автоматическое получение SSL сертификатов

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly CERT_DIR="/etc/letsencrypt"
readonly CERTBOT_LOG="/var/log/certbot.log"

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

install_certbot() {
    print_info "Установка Certbot...")
    
    if command -v certbot > /dev/null; then
        print_info "Certbot уже установлен")
        return 0
    fi
    
    if [[ -f /etc/debian_version ]]; then
        apt-get update
        apt-get install -y certbot python3-certbot-nginx python3-certbot-dns-cloudflare
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y epel-release
        yum install -y certbot python3-certbot-nginx
    else
        print_error "Не поддерживаемый дистрибутив")
        exit 1
    fi
    
    print_success "Certbot установлен")
}

check_dns_record() {
    local domain=$1
    
    print_info "Проверка DNS записи для $domain...")
    
    # Проверяем A запись
    local domain_ip=$(dig +short A "$domain" | head -1)
    local server_ip=$(curl -s ifconfig.me)
    
    if [ "$domain_ip" = "$server_ip" ]; then
        print_success "DNS запись настроена правильно")
        return 0
    else
        print_error "DNS запись не настроена!")
        print_info "Требуется: $domain → $server_ip")
        print_info "Текущее:  $domain → $domain_ip")
        return 1
    fi
}

obtain_certificate_standalone() {
    local domain=$1
    local email=${2:-"admin@$domain"}
    
    print_info "Получение SSL сертификата для $domain...")
    
    # Останавливаем службы на порту 80
    stop_services_on_port_80
    
    # Получаем сертификат
    if certbot certonly --standalone \
        --agree-tos \
        --no-eff-email \
        --email "$email" \
        -d "$domain" \
        --non-interactive; then
        
        print_success "Сертификат получен успешно")
        return 0
    else
        print_error "Не удалось получить сертификат")
        return 1
    fi
}

obtain_certificate_webroot() {
    local domain=$1
    local email=${2:-"admin@$domain"}
    local webroot="/var/www/html"
    
    print_info "Получение сертификата через webroot...")
    
    # Создаем директорию для проверки
    mkdir -p "$webroot/.well-known/acme-challenge"
    
    # Получаем сертификат
    if certbot certonly --webroot \
        --agree-tos \
        --no-eff-email \
        --email "$email" \
        -w "$webroot" \
        -d "$domain" \
        --non-interactive; then
        
        print_success "Сертификат получен")
        return 0
    else
        print_error "Не удалось получить сертификат")
        return 1
    fi
}

obtain_wildcard_certificate() {
    local domain=$1
    local email=${2:-"admin@$domain"}
    
    print_info "Получение wildcard сертификата для *.$domain...")
    
    # Для wildcard нужен DNS провайдер
    print_info "Настройте DNS провайдера в /etc/letsencrypt/cloudflare.ini")
    print_info "Формат: dns_cloudflare_api_token = YOUR_API_TOKEN")
    
    read -p "Продолжить? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    if certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
        --agree-tos \
        --no-eff-email \
        --email "$email" \
        -d "$domain" \
        -d "*.$domain" \
        --non-interactive; then
        
        print_success "Wildcard сертификат получен")
        return 0
    else
        print_error "Не удалось получить wildcard сертификат")
        return 1
    fi
}

setup_auto_renewal() {
    print_info "Настройка автоматического обновления...")
    
    # Проверяем существование cron задачи
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        # Добавляем задачу
        local cron_cmd="0 3 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'"
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        
        print_success "Автообновление настроено (ежедневно в 3:00)")
    else
        print_info "Автообновление уже настроено")
    fi
}

stop_services_on_port_80() {
    print_info "Остановка служб на порту 80...")
    
    # Останавливаем Nginx
    if systemctl is-active nginx > /dev/null; then
        systemctl stop nginx
        print_info "Nginx остановлен")
    fi
    
    # Останавливаем Apache
    if systemctl is-active apache2 > /dev/null; then
        systemctl stop apache2
        print_info "Apache остановлен")
    fi
    
    # Проверяем другие службы
    local port_80_pids=$(lsof -ti:80 2>/dev/null || true)
    if [ -n "$port_80_pids" ]; then
        print_warning "Найдены процессы на порту 80: $port_80_pids")
        read -p "Остановить их? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            kill -9 $port_80_pids 2>/dev/null || true
        fi
    fi
}

show_certificate_info() {
    local domain=$1
    
    print_info "Информация о сертификате для $domain...")
    
    local cert_path="$CERT_DIR/live/$domain/fullchain.pem"
    
    if [ ! -f "$cert_path" ]; then
        print_error "Сертификат не найден: $cert_path")
        return 1
    fi
    
    echo -e "\n${CYAN}=== ИНФОРМАЦИЯ О СЕРТИФИКАТЕ ===${NC}"
    
    # Показываем детали сертификата
    openssl x509 -in "$cert_path" -noout -text | grep -A1 "Subject:" | tail -1
    openssl x509 -in "$cert_path" -noout -dates
    openssl x509 -in "$cert_path" -noout -issuer | cut -d'=' -f2- | sed 's/^/\t/'
    
    # Показываем оставшиеся дни
    local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
    local expiry_seconds=$(date -d "$expiry_date" +%s)
    local current_seconds=$(date +%s)
    local days_left=$(( (expiry_seconds - current_seconds) / 86400 ))
    
    echo -e "\n${CYAN}Дней до истечения:${NC} $days_left"
    
    if [ $days_left -lt 30 ]; then
        print_warning "Сертификат истекает через $days_left дней!")
    else
        print_success "Сертификат действителен еще $days_left дней")
    fi
    
    # Показываем SAN (Subject Alternative Names)
    echo -e "\n${CYAN}Альтернативные имена:${NC}"
    openssl x509 -in "$cert_path" -noout -text | grep -A1 "X509v3 Subject Alternative Name" | tail -1 | sed 's/DNS://g' | tr ',' '\n' | sed 's/^/\t/'
}

create_certificate_symlinks() {
    local domain=$1
    local target_dir=$2
    
    print_info "Создание симлинков для $domain...")
    
    mkdir -p "$target_dir"
    
    # Создаем симлинки
    ln -sf "$CERT_DIR/live/$domain/fullchain.pem" "$target_dir/cert.pem"
    ln -sf "$CERT_DIR/live/$domain/privkey.pem" "$target_dir/key.pem"
    ln -sf "$CERT_DIR/live/$domain/chain.pem" "$target_dir/chain.pem"
    
    # Проверяем
    if [ -f "$target_dir/cert.pem" ] && [ -L "$target_dir/cert.pem" ]; then
        print_success "Симлинки созданы в $target_dir")
    else
        print_error "Не удалось создать симлинки")
    fi
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    local domain=${1:-""}
    local email=${2:-""}
    local method=${3:-"standalone"}
    
    print_info "Настройка Let's Encrypt SSL сертификатов")
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root")
        exit 1
    fi
    
    if [ -z "$domain" ]; then
        read -p "Введите доменное имя: " domain
        if [ -z "$domain" ]; then
            print_error "Домен не может быть пустым")
            exit 1
        fi
    fi
    
    if [ -z "$email" ]; then
        email="admin@$domain"
    fi
    
    # Установка Certbot
    install_certbot
    
    # Проверка DNS
    check_dns_record "$domain"
    
    # Получение сертификата
    case $method in
        "standalone")
            obtain_certificate_standalone "$domain" "$email"
            ;;
        "webroot")
            obtain_certificate_webroot "$domain" "$email"
            ;;
        "wildcard")
            obtain_wildcard_certificate "$domain" "$email"
            ;;
        *)
            print_error "Неизвестный метод: $method")
            exit 1
            ;;
    esac
    
    # Настройка автообновления
    setup_auto_renewal
    
    # Показываем информацию
    show_certificate_info "$domain"
    
    print_success "SSL сертификат настроен для $domain")
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [домен] [email] [метод]"
        echo ""
        echo "Методы получения сертификата:"
        echo "  standalone   - Автономный режим (останавливает порт 80)"
        echo "  webroot      - Через webroot директорию"
        echo "  wildcard     - Wildcard сертификат (требует DNS API)"
        echo ""
        echo "Примеры:"
        echo "  $0 example.com admin@example.com standalone"
        echo "  $0 --info example.com"
        echo "  $0 --symlink example.com /etc/nginx/ssl"
        ;;
    
    "--info")
        if [ -z "$2" ]; then
            print_error "Укажите домен: $0 --info example.com")
            exit 1
        fi
        show_certificate_info "$2"
        ;;
    
    "--symlink")
        if [ $# -lt 3 ]; then
            print_error "Используйте: $0 --symlink домен целевая_директория")
            exit 1
        fi
        create_certificate_symlinks "$2" "$3"
        ;;
    
    "--renew")
        print_info "Принудительное обновление сертификатов...")
        certbot renew --force-renewal
        print_success "Сертификаты обновлены")
        ;;
    
    *)
        main "$@"
        ;;
esac