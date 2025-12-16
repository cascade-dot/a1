#!/bin/bash
# modules/port-forwarding/nftables.sh - Настройка проброса через nftables

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/colors.sh"
source "$SCRIPT_DIR/../../utils/logger.sh"

# Конфигурация
readonly NFT_CONFIG="/etc/nftables.conf"
readonly BACKUP_DIR="/var/backups/nftables"
readonly CONFIG_DIR="/etc/cascade-vpn/nft-forwarding"

# ------------------------------------------------------------------------------
# ФУНКЦИИ
# ------------------------------------------------------------------------------

check_nftables() {
    if ! command -v nft > /dev/null; then
        print_info "nftables не установлен. Устанавливаем..."
        
        if [[ -f /etc/debian_version ]]; then
            apt-get update && apt-get install -y nftables
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y nftables
        else
            print_error "Не удалось установить nftables"
            exit 1
        fi
    fi
    
    # Отключаем iptables если используется
    if systemctl is-active iptables > /dev/null 2>&1; then
        print_info "Отключаем iptables..."
        systemctl stop iptables
        systemctl disable iptables
    fi
    
    # Запускаем nftables
    systemctl enable nftables
    systemctl start nftables
    
    print_success "nftables установлен и запущен"
}

create_base_config() {
    print_info "Создание базовой конфигурации nftables..."
    
    cat > "$NFT_CONFIG" << 'EOF'
#!/usr/sbin/nft -f

# Flush existing rules
flush ruleset

# Define variables
define wan_if = eth0
define lan_if = wg0

# Create tables
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow established/related connections
        ct state established,related accept
        
        # Allow loopback
        iif lo accept
        
        # Allow ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        
        # Allow SSH
        tcp dport 22 accept
        
        # Allow HTTP/HTTPS for ACME
        tcp dport {80, 443} accept
        
        # Allow WireGuard
        udp dport 51820 accept
        
        # Log dropped packets
        log prefix "nftables-input-drop: " limit rate 3/second
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Allow established/related
        ct state established,related accept
        
        # Allow forwarding between interfaces
        iif $lan_if oif $wan_if accept
        iif $wan_if oif $lan_if ct state established,related accept
        
        # Log dropped packets
        log prefix "nftables-forward-drop: " limit rate 3/second
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority -100; policy accept;
        
        # Port forwarding rules will be added here
    }
    
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        
        # MASQUERADE for outbound traffic
        oif $wan_if masquerade
    }
}
EOF
    
    # Применяем конфигурацию
    nft -f "$NFT_CONFIG"
    
    print_success "Базовая конфигурация nftables создана"
}

add_nft_port_forward() {
    local local_port=$1
    local remote_ip=$2
    local remote_port=$3
    local protocol=${4:-"tcp"}
    
    print_info "Добавление проброса через nftables: $local_port -> $remote_ip:$remote_port"
    
    # Создаем правило nftables
    local nft_cmd="add rule ip nat prerouting iif eth0 $protocol dport $local_port dnat to $remote_ip:$remote_port"
    
    # Добавляем правило
    nft "$nft_cmd"
    
    # Также добавляем правило в конфиг файл
    local rule_line="    # Forward $protocol port $local_port to $remote_ip:$remote_port"
    local insert_line="    $protocol dport $local_port dnat to $remote_ip:$remote_port"
    
    # Вставляем правило в конфиг
    sed -i "/# Port forwarding rules will be added here/a $rule_line\n$insert_line" "$NFT_CONFIG"
    
    # Сохраняем правило в отдельный конфиг
    save_nft_rule "$local_port" "$protocol" "$remote_ip" "$remote_port"
    
    # Перезагружаем nftables
    nft -f "$NFT_CONFIG"
    
    print_success "Правило nftables добавлено"
}

save_nft_rule() {
    local local_port=$1
    local protocol=$2
    local remote_ip=$3
    local remote_port=$4
    
    mkdir -p "$CONFIG_DIR"
    
    local rule_file="$CONFIG_DIR/rule_${local_port}_${protocol}.nft"
    
    cat > "$rule_file" << EOF
# nftables port forward rule
add rule ip nat prerouting iif eth0 $protocol dport $local_port dnat to $remote_ip:$remote_port
EOF
    
    print_debug "Правило nft сохранено в $rule_file"
}

show_nft_rules() {
    print_info "Текущие правила nftables:"
    
    echo -e "\n${CYAN}=== NAT PREROUTING ===${NC}"
    nft list chain ip nat prerouting
    
    echo -e "\n${CYAN}=== FILTER FORWARD ===${NC}"
    nft list chain inet filter forward
    
    echo -e "\n${CYAN}=== СОХРАНЕННЫЕ КОНФИГИ ===${NC}"
    if [ -d "$CONFIG_DIR" ]; then
        ls -la "$CONFIG_DIR/"
    else
        echo "  Директория конфигов пуста"
    fi
}

# ------------------------------------------------------------------------------
# ОСНОВНАЯ ФУНКЦИЯ
# ------------------------------------------------------------------------------

main() {
    print_info "Настройка проброса портов через nftables"
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуются права root"
        exit 1
    fi
    
    check_nftables
    create_base_config
    
    # Пример добавления проброса
    # add_nft_port_forward 2222 "10.0.0.2" 22 "tcp"
    
    print_success "nftables настроен"
    echo "Используйте команду 'nft' для управления правилами"
    echo "Конфигурация сохранена в: $NFT_CONFIG"
}

# ------------------------------------------------------------------------------
# ЗАПУСК
# ------------------------------------------------------------------------------

case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0"
        echo ""
        echo "Настройка nftables для проброса портов"
        echo ""
        echo "Ручное управление:"
        echo "  nft list ruleset          # Показать все правила"
        echo "  nft -f $NFT_CONFIG       # Применить конфиг"
        echo "  nft flush ruleset        # Очистить все правила"
        ;;
    *)
        main
        ;;
esac