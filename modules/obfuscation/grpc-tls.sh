#!/bin/bash
# modules/obfuscation/grpc-tls.sh - Настройка gRPC + TLS (маскировка под Google сервисы)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly XRAY_DIR="/etc/xray-grpc"
readonly CONFIG_FILE="$XRAY_DIR/config.json"
readonly DEFAULT_PORT=443
readonly SERVICE_NAME="google-grpc-service"  # Маскировка под Google сервис

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

check_xray() {
    if ! command -v xray > /dev/null; then
        print_info "Xray не установлен. Устанавливаем...")
        install_xray
    fi
}

install_xray() {
    print_info "Установка Xray-core...")
    
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        *) ARCH="64" ;;
    esac
    
    local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH}.zip"
    
    wget -O /tmp/xray.zip "$xray_url"
    unzip -o /tmp/xray.zip xray -d /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    mkdir -p "$XRAY_DIR" /var/log/xray-grpc
    
    print_success "Xray-core установлен")
}

configure_grpc() {
    local port=$1
    local domain=$2
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local service_name="${SERVICE_NAME}-$(openssl rand -hex 3)"
    
    print_info "Конфигурация gRPC + TLS...")
    print_info "Service Name: $service_name")
    
    # Создаем конфиг Xray с gRPC транспортом
    cat > "$CONFIG_FILE" << EOF
{
    "log": {
        "loglevel": "warning",
        "access": "/var/log/xray-grpc/access.log",
        "error": "/var/log/xray-grpc/error.log"
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
                "network": "grpc",
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
                "grpcSettings": {
                    "serviceName": "$service_name",
                    "multiMode": true,
                    "idle_timeout": 60,
                    "health_check_timeout": 20,
                    "permit_without_stream": false,
                    "initial_windows_size": 524288
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
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": []
    }
}
EOF
    
    print_success "Конфигурация gRPC создана")
    print_info "UUID: $uuid")
    print_info "Service Name: $service_name")
    
    echo "$uuid" > "$XRAY_DIR/uuid.txt"
    echo "$service_name" > "$XRAY_DIR/service-name.txt"
}

setup_tls_certificates() {
    local domain=$1
    
    print_info "Настройка TLS сертификатов для $domain...")
    
    # Используем существующие сертификаты или создаем новые
    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        print_info "Используем Let's Encrypt сертификаты...")
        cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$XRAY_DIR/cert.pem"
        cp "/etc/letsencrypt/live/$domain/privkey.pem" "$XRAY_DIR/key.pem"
    else
        print_info "Создаем самоподписанный сертификат...")
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$XRAY_DIR/key.pem" \
            -out "$XRAY_DIR/cert.pem" \
            -subj "/C=US/ST=California/L=Mountain View/O=Google LLC/CN=$domain" \
            2>/dev/null
    fi
    
    chmod 600 "$XRAY_DIR"/*.pem
    
    print_success "TLS сертификаты настроены")
}

setup_systemd_service() {
    print_info "Настройка systemd службы...")
    
    cat > /etc/systemd/system/xray-grpc.service << EOF
[Unit]
Description=Xray gRPC Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config $CONFIG_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

# Google-like process names for obfuscation
ExecStartPre=/bin/bash -c 'sleep 1 && ps -ef | grep xray | grep -v grep | awk \"{print \\\$2}\" | xargs -I{} renice -n -10 {} 2>/dev/null || true'
ExecStartPost=/bin/bash -c 'sleep 2 && ps -ef | grep xray | grep -v grep | awk \"{print \\\$2}\" | xargs -I{} renice -n -10 {} 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable xray-grpc.service
    
    print_success "Systemd служба настроена")
}

generate_client_config() {
    local domain=$1
    local port=$2
    
    local uuid=$(cat "$XRAY_DIR/uuid.txt")
    local service_name=$(cat "$XRAY_DIR/service-name.txt")
    
    print_info "Генерация клиентской конфигурации...")
    
    # Конфиг для Xray клиента
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
                "network": "grpc",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$domain",
                    "allowInsecure": false,
                    "alpn": ["h2", "http/1.1"]
                },
                "grpcSettings": {
                    "serviceName": "$service_name",
                    "multiMode": true
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
    
    # Генерация ссылки
    local encoded_uuid=$(echo -n "$uuid" | base64 | tr -d '\n' | tr '+/' '-_')
    local grpc_url="vless://$uuid@$domain:$port?type=grpc&security=tls&serviceName=$(echo -n "$service_name" | jq -sRr @uri)&flow=xtls-rprx-vision#gRPC-TLS"
    
    echo "$grpc_url" > "$XRAY_DIR/client-url.txt"
    
    # QR код
    if command -v qrencode > /dev/null; then
        qrencode -o "$XRAY_DIR/client-qr.png" -t PNG "$grpc_url"
    fi
    
    print_success "Клиентский конфиг создан")
}

setup_nginx_masquerade() {
    local domain=$1
    local port=$2
    
    print_info "Настройка Nginx для маскировки под Google сервисы...")
    
    if ! command -v nginx > /dev/null; then
        print_info "Установка Nginx...")
        if [[ -f /etc/debian_version ]]; then
            apt-get install -y nginx
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y nginx
        fi
    fi
    
    # Создаем конфиг Nginx
    cat > /etc/nginx/sites-available/grpc-service << EOF
server {
    listen $port ssl http2;
    listen [::]:$port ssl http2;
    
    server_name $domain;
    
    ssl_certificate $XRAY_DIR/cert.pem;
    ssl_certificate_key $XRAY_DIR/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    
    # gRPC specific settings
    http2_body_preread_size 128k;
    http2_idle_timeout 15m;
    
    location / {
        # Маскировка под Google сервис
        add_header X-Content-Type-Options "nosniff";
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-XSS-Protection "1; mode=block";
        
        # Google-like headers
        add_header Alt-Svc 'h3=":443"; ma=86400';
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        
        # Фейковый ответ
        return 200 '{"service":"google-grpc-service","status":"operational","version":"2.1.0"}';
    }
    
    # Реальный gRPC endpoint
    location ~ ^/.*/.*/.*$ {
        grpc_pass grpc://127.0.0.1:${port};
        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        
        # gRPC specific
        grpc_read_timeout 3600s;
        grpc_send_timeout 3600s;
        grpc_buffer_size 128k;
    }
}
EOF
    
    # Активируем конфиг
    ln -sf /etc/nginx/sites-available/grpc-service /etc/nginx/sites-enabled/
    
    # Перезапускаем Nginx
    systemctl restart nginx
    
    print_success "Nginx настроен для маскировки")
}

show_connection_info() {
    local domain=${1:-$(curl -s ifconfig.me)}
    local port=${2:-$DEFAULT_PORT}
    
    local uuid=$(cat "$XRAY_DIR/uuid.txt" 2>/dev/null || echo "не найден")
    local service_name=$(cat "$XRAY_DIR/service-name.txt" 2>/dev/null || echo "не найден")
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}          gRPC + TLS НАСТРОЕН (Google маскировка)              ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}▸ ПАРАМЕТРЫ ПОДКЛЮЧЕНИЯ:${NC}"
    echo -e "  Домен:      ${YELLOW}$domain${NC}"
    echo -e "  Порт:       ${YELLOW}$port${NC}"
    echo -e "  Протокол:   ${YELLOW}gRPC + TLS${NC}"
    echo -e "  UUID:       ${YELLOW}$uuid${NC}"
    echo -e "  Service:    ${YELLOW}$service_name${NC}"
    
    echo -e "\n${CYAN}▸ МАСКИРОВКА:${NC}"
    echo -e "  Трафик выглядит как: ${YELLOW}Google gRPC сервис${NC}"
    echo -e "  Сервис маскировки: ${YELLOW}Nginx reverse proxy${NC}"
    echo -e "  ALPN: ${YELLOW}h2, http/1.1${NC}"
    
    echo -e "\n${CYAN}▸ ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo -e "  1. Требуется Xray-core ≥ v1.8.0"
    echo -e "  2. Импортируйте конфиг: ${WHITE}$XRAY_DIR/client.json${NC}"
    echo -e "  3. Или используйте ссылку: ${WHITE}$XRAY_DIR/client-url.txt${NC}"
    
    echo -e "\n${CYAN}▸ КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
    echo -e "  Статус:     ${WHITE}systemctl status xray-grpc${NC}"
    echo -e "  Логи:       ${WHITE}tail -f /var/log/xray-grpc/access.log${NC}"
    echo -e "  Nginx:      ${WHITE}systemctl status nginx${NC}"
    
    echo -e "\n${YELLOW}⚠️  ПРЕИМУЩЕСТВА gRPC:${NC}"
    echo "  • Маскировка под легитимный Google трафик"
    echo "  • Мультиплексирование (несколько потоков в одном соединении)"
    echo "  • Высокая производительность и низкие задержки"
    echo "  • Поддержка health checks и keepalive"
    
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    local port=${1:-$DEFAULT_PORT}
    local domain=${2:-$(curl -s ifconfig.me)}
    
    print_info "Настройка gRPC + TLS с Google маскировкой...")
    print_info "Порт: $port, Домен: $domain")
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root")
        exit 1
    fi
    
    # Установка и настройка
    check_xray
    setup_tls_certificates "$domain"
    configure_grpc "$port" "$domain"
    setup_systemd_service
    setup_nginx_masquerade "$domain" "$port"
    generate_client_config "$domain" "$port"
    
    # Запуск служб
    systemctl start xray-grpc.service
    
    # Информация
    show_connection_info "$domain" "$port"
    
    print_success "gRPC + TLS с маскировкой настроен!")
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [порт] [домен]"
        echo ""
        echo "gRPC + TLS маскировка под Google сервисы:"
        echo "  • Трафик выглядит как легитимный Google gRPC"
        echo "  • Nginx reverse proxy для дополнительной маскировки"
        echo "  • Поддержка мультиплексирования и health checks"
        echo ""
        echo "Пример: $0 443 grpc.google-services.com"
        echo "Пример: $0 8443 \$(curl -s ifconfig.me)"
        ;;
    *)
        main "$@"
        ;;
esac