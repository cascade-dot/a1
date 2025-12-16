#!/bin/bash
# modules/certificates/selfsigned.sh - Создание самоподписанных SSL сертификатов

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly CERTS_DIR="/etc/ssl/certs"
readonly PRIVATE_DIR="/etc/ssl/private"
readonly DEFAULT_DAYS=365
readonly DEFAULT_BITS=2048

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

create_ca_certificate() {
    print_info "Создание корневого CA сертификата...")
    
    mkdir -p "$CERTS_DIR/ca" "$PRIVATE_DIR/ca"
    
    # Создаем приватный ключ CA
    openssl genrsa -out "$PRIVATE_DIR/ca/ca.key" 4096 2>/dev/null
    chmod 600 "$PRIVATE_DIR/ca/ca.key"
    
    # Создаем самоподписанный CA сертификат
    cat > "$CERTS_DIR/ca/ca.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = California
L = San Francisco
O = Cascade VPN CA
CN = Cascade VPN Root CA

[v3_req]
keyUsage = keyCertSign, cRLSign
basicConstraints = CA:TRUE
subjectKeyIdentifier = hash
EOF
    
    openssl req -x509 -new -nodes \
        -key "$PRIVATE_DIR/ca/ca.key" \
        -days 3650 \
        -out "$CERTS_DIR/ca/ca.crt" \
        -config "$CERTS_DIR/ca/ca.cnf" \
        2>/dev/null
    
    print_success "CA сертификат создан")
    print_info "CA сертификат: $CERTS_DIR/ca/ca.crt")
    print_info "CA приватный ключ: $PRIVATE_DIR/ca/ca.key")
}

create_server_certificate() {
    local domain=$1
    local days=${2:-$DEFAULT_DAYS}
    local bits=${3:-$DEFAULT_BITS}
    
    print_info "Создание серверного сертификата для $domain...")
    
    mkdir -p "$CERTS_DIR/servers" "$PRIVATE_DIR/servers"
    
    # Создаем приватный ключ сервера
    openssl genrsa -out "$PRIVATE_DIR/servers/$domain.key" "$bits" 2>/dev/null
    chmod 600 "$PRIVATE_DIR/servers/$domain.key"
    
    # Создаем CSR (Certificate Signing Request)
    cat > "$CERTS_DIR/servers/$domain.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = California
L = San Francisco
O = Cascade VPN
CN = $domain

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = *.$domain
IP.1 = $(curl -s ifconfig.me)
EOF
    
    openssl req -new \
        -key "$PRIVATE_DIR/servers/$domain.key" \
        -out "$CERTS_DIR/servers/$domain.csr" \
        -config "$CERTS_DIR/servers/$domain.cnf" \
        2>/dev/null
    
    # Подписываем CSR с помощью CA
    openssl x509 -req \
        -in "$CERTS_DIR/servers/$domain.csr" \
        -CA "$CERTS_DIR/ca/ca.crt" \
        -CAkey "$PRIVATE_DIR/ca/ca.key" \
        -CAcreateserial \
        -out "$CERTS_DIR/servers/$domain.crt" \
        -days "$days" \
        -extfile "$CERTS_DIR/servers/$domain.cnf" \
        -extensions v3_req \
        2>/dev/null
    
    # Создаем полную цепочку
    cat "$CERTS_DIR/servers/$domain.crt" "$CERTS_DIR/ca/ca.crt" > "$CERTS_DIR/servers/$domain-fullchain.crt"
    
    print_success "Серверный сертификат создан")
    print_info "Сертификат: $CERTS_DIR/servers/$domain.crt")
    print_info "Полная цепочка: $CERTS_DIR/servers/$domain-fullchain.crt")
    print_info "Приватный ключ: $PRIVATE_DIR/servers/$domain.key")
}

create_client_certificate() {
    local client_name=$1
    local days=${2:-365}
    
    print_info "Создание клиентского сертификата для $client_name...")
    
    mkdir -p "$CERTS_DIR/clients" "$PRIVATE_DIR/clients"
    
    # Создаем приватный ключ клиента
    openssl genrsa -out "$PRIVATE_DIR/clients/$client_name.key" 2048 2>/dev/null
    chmod 600 "$PRIVATE_DIR/clients/$client_name.key"
    
    # Создаем CSR
    cat > "$CERTS_DIR/clients/$client_name.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = California
L = San Francisco
O = Cascade VPN Client
CN = $client_name

[v3_req]
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
EOF
    
    openssl req -new \
        -key "$PRIVATE_DIR/clients/$client_name.key" \
        -out "$CERTS_DIR/clients/$client_name.csr" \
        -config "$CERTS_DIR/clients/$client_name.cnf" \
        2>/dev/null
    
    # Подписываем
    openssl x509 -req \
        -in "$CERTS_DIR/clients/$client_name.csr" \
        -CA "$CERTS_DIR/ca/ca.crt" \
        -CAkey "$PRIVATE_DIR/ca/ca.key" \
        -CAcreateserial \
        -out "$CERTS_DIR/clients/$client_name.crt" \
        -days "$days" \
        -extfile "$CERTS_DIR/clients/$client_name.cnf" \
        -extensions v3_req \
        2>/dev/null
    
    # Создаем PKCS12 (для импорта в браузеры)
    openssl pkcs12 -export \
        -out "$CERTS_DIR/clients/$client_name.p12" \
        -inkey "$PRIVATE_DIR/clients/$client_name.key" \
        -in "$CERTS_DIR/clients/$client_name.crt" \
        -certfile "$CERTS_DIR/ca/ca.crt" \
        -password pass:"$client_name" \
        2>/dev/null
    
    print_success "Клиентский сертификат создан")
    print_info "Сертификат: $CERTS_DIR/clients/$client_name.crt")
    print_info "PKCS12: $CERTS_DIR/clients/$client_name.p12 (пароль: $client_name)")
}

verify_certificate() {
    local cert_file=$1
    
    print_info "Проверка сертификата $cert_file...")
    
    if [ ! -f "$cert_file" ]; then
        print_error "Файл не найден: $cert_file")
        return 1
    fi
    
    # Проверяем сертификат
    openssl x509 -in "$cert_file" -noout -text | head -20
    
    # Проверяем срок действия
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local expiry_seconds=$(date -d "$expiry_date" +%s)
    local current_seconds=$(date +%s)
    local days_left=$(( (expiry_seconds - current_seconds) / 86400 ))
    
    echo -e "\n${CYAN}Дней до истечения:${NC} $days_left"
    
    if [ $days_left -lt 30 ]; then
        print_warning "Сертификат истекает через $days_left дней!")
    else
        print_success "Сертификат действителен еще $days_left дней")
    fi
    
    # Проверяем цепочку
    if openssl verify -CAfile "$CERTS_DIR/ca/ca.crt" "$cert_file" 2>/dev/null; then
        print_success "Цепочка сертификатов валидна")
    else
        print_warning "Проблемы с цепочкой сертификатов")
    fi
}

create_certificate_bundle() {
    local domain=$1
    local target_dir=$2
    
    print_info "Создание бандла сертификатов для $domain...")
    
    mkdir -p "$target_dir"
    
    # Копируем файлы
    cp "$CERTS_DIR/servers/$domain-fullchain.crt" "$target_dir/fullchain.pem"
    cp "$CERTS_DIR/servers/$domain.crt" "$target_dir/cert.pem"
    cp "$PRIVATE_DIR/servers/$domain.key" "$target_dir/privkey.pem"
    cp "$CERTS_DIR/ca/ca.crt" "$target_dir/ca.crt"
    
    # Создаем объединенный файл для Nginx
    cat "$CERTS_DIR/servers/$domain.crt" \
        "$CERTS_DIR/servers/$domain-fullchain.crt" \
        "$PRIVATE_DIR/servers/$domain.key" > "$target_dir/nginx.pem"
    
    # Права доступа
    chmod 600 "$target_dir"/*.pem "$target_dir"/*.key
    chmod 644 "$target_dir"/*.crt
    
    print_success "Бандл создан в $target_dir")
    print_info "Для Nginx используйте: ssl_certificate $target_dir/nginx.pem")
}

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         САМОПОДПИСАННЫЕ SSL СЕРТИФИКАТЫ                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${GREEN}[1]${NC} Создать корневой CA сертификат"
    echo -e "${GREEN}[2]${NC} Создать серверный сертификат"
    echo -e "${GREEN}[3]${NC} Создать клиентский сертификат"
    echo -e "${GREEN}[4]${NC} Проверить сертификат"
    echo -e "${GREEN}[5]${NC} Создать бандл для Nginx"
    echo -e "${GREEN}[6]${NC} Экспорт CA для клиентов"
    echo -e "${WHITE}[0]${NC} Выход\n"
    
    read -p "Выберите действие (0-6): " choice
    
    case $choice in
        1)
            create_ca_certificate
            ;;
        2)
            read -p "Доменное имя: " domain
            read -p "Срок действия (дней) [365]: " days
            days=${days:-365}
            
            create_server_certificate "$domain" "$days"
            ;;
        3)
            read -p "Имя клиента: " client_name
            create_client_certificate "$client_name"
            ;;
        4)
            read -p "Путь к сертификату: " cert_file
            verify_certificate "$cert_file"
            ;;
        5)
            read -p "Доменное имя: " domain
            read -p "Целевая директория: " target_dir
            target_dir=${target_dir:-"/etc/nginx/ssl"}
            
            create_certificate_bundle "$domain" "$target_dir"
            ;;
        6)
            print_info "CA сертификат для импорта в клиенты:")
            echo ""
            cat "$CERTS_DIR/ca/ca.crt"
            echo ""
            print_info "Скопируйте содержимое выше в файл .crt на клиенте")
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
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    print_info "Управление самоподписанными SSL сертификатами")
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root")
        exit 1
    fi
    
    # Создаем базовые директории
    mkdir -p "$CERTS_DIR" "$PRIVATE_DIR"
    
    # Показываем меню
    show_menu
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0"
        echo ""
        echo "Создание и управление самоподписанными SSL сертификатами:"
        echo "  • Корневой CA сертификат"
        echo "  • Серверные сертификаты"
        echo "  • Клиентские сертификаты"
        echo "  • Проверка и верификация"
        echo "  • Бандлы для веб-серверов"
        echo ""
        echo "Для интерактивного режима запустите без аргументов.")
        ;;
    *)
        main
        ;;
esac