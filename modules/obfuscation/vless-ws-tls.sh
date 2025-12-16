#!/bin/bash
# modules/obfuscation/vless-ws-tls.sh - Настройка VLESS + WebSocket + TLS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly XRAY_DIR="/etc/xray"
readonly CONFIG_FILE="$XRAY_DIR/config.json"
readonly DEFAULT_PORT=443
readonly DEFAULT_DOMAIN=""

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

check_xray() {
    if ! command -v xray > /dev/null; then
        print_info "Xray не установлен. Устанавливаем..."
        install_xray
    fi
}

install_xray() {
    print_info "Установка Xray-core..."
    
    # Определяем архитектуру
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        armv7l) ARCH="arm32-v7a" ;;
        *) ARCH="64" ;;
    esac
    
    # Скачиваем Xray
    local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH}.zip"
    
    wget -O /tmp/xray.zip "$xray_url"
    unzip -o /tmp/xray.zip xray -d /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    # Создаем директории
    mkdir -p "$XRAY_DIR" /var/log/xray
    
    print_success "Xray-core установлен"
}

configure_tls() {
    local domain=$1
    
    print_info "Настройка TLS для домена: $domain"
    
    if [ -z "$domain" ]; then
        print_warning "Домен не указан. Используем самоподписанный сертификат."
        create_selfsigned_cert
        return
    fi
    
    # Проверяем доступность домена
    if ! nslookup "$domain" > /dev/null 2>&1; then
        print_warning "Домен $domain не резолвится. Используем самоподписанный сертификат."
        create_selfsigned_cert "$domain"
        return
    fi
    
    # Пробуем получить Let's Encrypt сертификат
    if command -v certbot > /dev/null; then
        print_info "Пытаемся получить Let's Encrypt сертификат..."
        
        # Останавливаем сервисы на порту 80
        systemctl stop nginx 2>/dev/null || true
        
        if certbot certonly --standalone --agree-tos --no-eff-email \
            -d "$domain" --email admin@$domain --non-interactive; then
            
            # Создаем символические ссылки
            ln -sf /etc/letsencrypt/live/$domain/fullchain.pem "$XRAY_DIR/cert.pem"
            ln -sf /etc/letsencrypt/live/$domain/privkey.pem "$XRAY_DIR/key.pem"
            
            # Настройка автообновления
            (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl restart xray'") | crontab -
            
            print_success "Let's Encrypt сертификат получен"
            return
        fi
    fi
    
    # Если не удалось получить LE сертификат
    print_warning "Не удалось получить Let's Encrypt сертификат. Используем самоподписанный."
    create_selfsigned_cert "$domain"
}

create_selfsigned_cert() {
    local domain=${1:-$(hostname)}
    
    print_info "Создание самоподписанного сертификата для $domain"
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$XRAY_DIR/key.pem" \
        -out "$XRAY_DIR/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" \
        2>/dev/null
    
    chmod 600 "$XRAY_DIR"/*.pem
    
    print_success "Самоподписанный сертификат создан"
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

create_xray_config() {
    local port=$1
    local domain=$2
    local uuid=$3
    local path="/$(openssl rand -hex 4)/"
    
    print_info "Создание конфигурации Xray..."
    
    cat > "$CONFIG_FILE" << EOF
{
    "log": {
        "loglevel": "warning",
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log"
    },
    "inbounds": [
        {
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$domain",
                    "certificates": [
                        {
                            "certificateFile": "$XRAY_DIR/cert.pem",
                            "keyFile": "$XRAY_DIR/key.pem"
                        }
                    ],
                    "alpn": ["h2", "http/1.1"]
                },
                "wsSettings": {
                    "path": "$path",
                    "headers": {
                        "Host": "$domain"
                    }
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]
}
EOF
    
    print_success "Конфигурация Xray создана"
    print_info "UUID: $uuid"
    print_info "WebSocket путь: $path"
}

setup_systemd_service() {
    print_info "Настройка systemd службы..."
    
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config $CONFIG_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable xray.service
    
    print_success "Systemd служба настроена"
}

setup_firewall() {
    local port=$1
    
    print_info "Настройка фаервола для порта $port..."
    
    if command -v ufw > /dev/null; then
        ufw allow $port/tcp comment "VLESS+WS+TLS"
        ufw reload
    elif command -v firewall-cmd > /dev/null; then
        firewall-cmd --permanent --add-port=$port/tcp
        firewall-cmd --reload
    fi
    
    print_success "Фаервол настроен"
}

generate_client_config() {
    local domain=$1
    local port=$2
    local uuid=$3
    local path=$(grep -oP '"path": "\K[^"]+' "$CONFIG_FILE")
    
    print_info "Генерация клиентской конфигурации..."
    
    cat > "$XRAY_DIR/client.json" << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 10808,
            "listen": "127.0.0.1",
            "protocol": "socks",
            "settings": {
                "udp": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "$domain",
                        "port": $port,
                        "users": [
                            {
                                "id": "$uuid",
                                "encryption": "none",
                                "flow": "xtls-rprx-vision"
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$domain",
                    "allowInsecure": false
                },
                "wsSettings": {
                    "path": "$path",
                    "headers": {
                        "Host": "$domain"
                    }
                }
            },
            "mux": {
                "enabled": true,
                "concurrency": 8
            }
        }
    ]
}
EOF
    
    # Генерация ссылки для v2rayN
    cat > "$XRAY_DIR/client-url.txt" << EOF
vless://$uuid@$domain:$port?type=ws&security=tls&path=$(echo $path | sed 's/\//%2F/g')&host=$domain&encryption=none&flow=xtls-rprx-vision#VLESS-WS-TLS
EOF
    
    print_success "Клиентская конфигурация создана"
    print_info "Файл конфига: $XRAY_DIR/client.json"
    print_info "Ссылка для v2rayN: $XRAY_DIR/client-url.txt"
}

show_connection_info() {
    local domain=$1
    local port=$2
    local uuid=$(grep -oP '"id": "\K[^"]+' "$CONFIG_FILE" | head -1)
    local path=$(grep -oP '"path": "\K[^"]+' "$CONFIG_FILE")
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}          VLESS + WebSocket + TLS НАСТРОЕН!                    ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}▸ ПАРАМЕТРЫ ПОДКЛЮЧЕНИЯ:${NC}"
    echo -e "  Адрес:     ${YELLOW}$domain${NC}"
    echo -e "  Порт:      ${YELLOW}$port${NC}"
    echo -e "  UUID:      ${YELLOW}$uuid${NC}"
    echo -e "  Протокол:  ${YELLOW}VLESS${NC}"
    echo -e "  Транспорт: ${YELLOW}WebSocket${NC}"
    echo -e "  Безопасность: ${YELLOW}TLS${NC}"
    echo -e "  Путь WS:   ${YELLOW}$path${NC}"
    
    echo -e "\n${CYAN}▸ ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo -e "  1. Установите v2rayN (Windows) или v2rayNG (Android)"
    echo -e "  2. Импортируйте конфиг из: ${WHITE}$XRAY_DIR/client.json${NC}"
    echo -e "  3. Или используйте ссылку из: ${WHITE}$XRAY_DIR/client-url.txt${NC}"
    
    echo -e "\n${CYAN}▸ КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
    echo -e "  Статус:    ${WHITE}systemctl status xray${NC}"
    echo -e "  Запуск:    ${WHITE}systemctl start xray${NC}"
    echo -e "  Остановка: ${WHITE}systemctl stop xray${NC}"
    echo -e "  Логи:      ${WHITE}tail -f /var/log/xray/access.log${NC}"
    
    echo -e "\n${YELLOW}⚠️  ВАЖНО:${NC}"
    echo "  1. Убедитесь, что домен $domain указывает на IP сервера"
    echo "  2. При использовании самоподписанного сертификата добавьте исключение"
    echo "  3. Проверьте работу: curl -I https://$domain:$port"
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    local port=${1:-$DEFAULT_PORT}
    local domain=${2:-$(curl -s ifconfig.me)}
    
    print_info "Настройка VLESS + WebSocket + TLS..."
    print_info "Порт: $port, Домен: $domain"
    
    # Проверка root
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root"
        exit 1
    fi
    
    # Установка и настройка
    check_xray
    configure_tls "$domain"
    
    local uuid=$(generate_uuid)
    create_xray_config "$port" "$domain" "$uuid"
    setup_systemd_service
    setup_firewall "$port"
    generate_client_config "$domain" "$port" "$uuid"
    
    # Запуск службы
    systemctl start xray.service
    
    # Информация
    show_connection_info "$domain" "$port"
    
    print_success "Настройка завершена!"
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [порт] [домен]"
        echo ""
        echo "Примеры:"
        echo "  $0 443 vpn.example.com     # Настройка на порту 443 с доменом"
        echo "  $0 8443                    # Настройка на порту 8443 с IP"
        echo "  $0 --help                  # Показать справку"
        ;;
    *)
        main "$@"
        ;;
esac