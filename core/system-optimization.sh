#!/bin/bash
# core/system-optimization.sh - Оптимизация системы для VPN

set -euo pipefail

SYSOPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SYSOPT_DIR/../utils/colors.sh"
source "$SYSOPT_DIR/../utils/logger.sh"
source "$SYSOPT_DIR/../utils/validators.sh"

# Оптимизация параметров ядра для высокой пропускной способности
optimize_kernel_parameters() {
    log_section_start "Kernel Parameters Optimization"
    
    print_info "Optimizing kernel parameters for VPN..."
    
    # Создаем конфиг для sysctl
    cat > /etc/sysctl.d/99-cascade-vpn.conf << 'EOF'
# Cascade VPN System Optimization

# IP Forwarding (необходимо для маршрутизации)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# TCP Optimization
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_syncookies = 1

# UDP Optimization
net.ipv4.udp_mem = 67108864 134217728 268435456

# Socket Optimization
net.core.somaxconn = 4096
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0

# Buffer Optimization
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.ipv4.tcp_rmem = 4096 87380 268435456
net.ipv4.tcp_wmem = 4096 65536 268435456
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Connection Tracking
net.netfilter.nf_conntrack_max = 2000000
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60

# IP Spoofing Protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ICMP Redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# ICMP Protection
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_ignore_bogus_error_responses = 1

# IPv6 Optimization
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2
EOF
    
    # Применяем параметры
    sysctl -p /etc/sysctl.d/99-cascade-vpn.conf > /dev/null
    log_success "Kernel parameters optimized"
    
    log_section_end "Kernel Parameters Optimization" "success"
}

# Оптимизация файловых дескрипторов
optimize_file_descriptors() {
    log_section_start "File Descriptors Optimization"
    
    print_info "Setting up file descriptor limits..."
    
    # Проверяем текущий лимит
    local current_limit=$(ulimit -n)
    print_debug "Current file descriptor limit: $current_limit"
    
    # Если лимит меньше чем требуется
    if ((current_limit < 65536)); then
        cat > /etc/security/limits.d/99-cascade-vpn.conf << 'EOF'
# Cascade VPN - File Descriptor Limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
root soft nofile 65536
root hard nofile 65536
root soft nproc 65536
root hard nproc 65536
EOF
        
        # Применяем изменения
        ulimit -n 65536 2>/dev/null || true
        log_success "File descriptor limits updated to 65536"
    else
        print_debug "File descriptor limit already adequate: $current_limit"
    fi
    
    log_section_end "File Descriptors Optimization" "success"
}

# Настройка сетевого стека для низкой задержки
optimize_network_stack() {
    log_section_start "Network Stack Optimization"
    
    print_info "Optimizing network stack for low latency..."
    
    # BBR congestion control
    if grep -q "tcp_congestion_control = bbr" /etc/sysctl.d/99-cascade-vpn.conf; then
        print_info "BBR congestion control will be enabled after reboot"
    fi
    
    # Включаем ECN (Explicit Congestion Notification)
    echo 1 > /proc/sys/net/ipv4/tcp_ecn 2>/dev/null || true
    
    # Включаем SACK для лучшей обработки пакетов
    echo 1 > /proc/sys/net/ipv4/tcp_sack 2>/dev/null || true
    
    log_success "Network stack optimized"
    log_section_end "Network Stack Optimization" "success"
}

# Настройка пула портов
optimize_port_ranges() {
    log_section_start "Port Range Optimization"
    
    # Увеличиваем диапазон портов для клиентских соединений
    local min_port=1024
    local max_port=65535
    
    echo "$min_port $max_port" > /proc/sys/net/ipv4/ip_local_port_range
    print_info "Port range configured: $min_port - $max_port"
    
    log_section_end "Port Range Optimization" "success"
}

# Отключение ненужных сервисов
disable_unnecessary_services() {
    log_section_start "Disabling Unnecessary Services"
    
    print_info "Checking for unnecessary services..."
    
    local services=(
        "avahi-daemon"
        "cups"
        "bluetooth"
        "iscsid"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" 2>/dev/null; then
            print_info "Disabling $service..."
            systemctl disable "$service" 2>/dev/null || true
            systemctl stop "$service" 2>/dev/null || true
            print_debug "✓ $service disabled"
        fi
    done
    
    log_success "Unnecessary services disabled"
    log_section_end "Disabling Unnecessary Services" "success"
}

# Настройка firewall (базовая)
setup_firewall() {
    log_section_start "Firewall Configuration"
    
    # Проверяем наличие firewalld или ufw
    if command_exists firewalld; then
        print_info "Configuring firewalld..."
        
        # Разрешаем SSH
        firewall-cmd --permanent --add-service=ssh > /dev/null 2>&1 || true
        
        # Разрешаем HTTP и HTTPS (для ACME)
        firewall-cmd --permanent --add-service=http > /dev/null 2>&1 || true
        firewall-cmd --permanent --add-service=https > /dev/null 2>&1 || true
        
        firewall-cmd --reload > /dev/null 2>&1 || true
        log_success "Firewalld configured"
    elif command_exists ufw; then
        print_info "Configuring UFW..."
        
        ufw default deny incoming > /dev/null 2>&1 || true
        ufw default allow outgoing > /dev/null 2>&1 || true
        ufw allow 22/tcp > /dev/null 2>&1 || true
        ufw allow 80/tcp > /dev/null 2>&1 || true
        ufw allow 443/tcp > /dev/null 2>&1 || true
        
        echo "y" | ufw enable > /dev/null 2>&1 || true
        log_success "UFW configured"
    else
        print_warning "No firewall found (firewalld/ufw). Manual firewall configuration recommended."
    fi
    
    log_section_end "Firewall Configuration" "success"
}

# Включить IP маскирование
enable_ip_masquerading() {
    log_section_start "IP Masquerading"
    
    print_info "Enabling IP masquerading..."
    
    # Получаем основной сетевой интерфейс
    local primary_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [[ -n "$primary_interface" ]]; then
        print_info "Primary interface: $primary_interface"
        
        # Используем nftables если доступно, иначе iptables
        if command_exists nft; then
            nft add table nat 2>/dev/null || true
            nft add chain nat postrouting '{ type nat hook postrouting priority 0; }' 2>/dev/null || true
            nft add rule nat postrouting oifname "$primary_interface" masquerade 2>/dev/null || true
            print_debug "IP masquerading configured with nftables"
        elif command_exists iptables; then
            iptables -t nat -A POSTROUTING -o "$primary_interface" -j MASQUERADE 2>/dev/null || true
            print_debug "IP masquerading configured with iptables"
        fi
        
        log_success "IP masquerading enabled for $primary_interface"
    else
        print_warning "Could not determine primary network interface"
    fi
    
    log_section_end "IP Masquerading" "success"
}

# Основная функция
main() {
    print_header "CASCADE VPN - System Optimization"
    
    check_root
    
    optimize_kernel_parameters
    optimize_file_descriptors
    optimize_network_stack
    optimize_port_ranges
    disable_unnecessary_services
    setup_firewall
    enable_ip_masquerading
    
    print_header "System Optimization Completed"
    print_info "Some optimizations will take effect after system reboot"
    
    return 0
}

# Исполнить если запущено как скрипт
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
