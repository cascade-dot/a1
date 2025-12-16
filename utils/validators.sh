#!/bin/bash
# utils/validators.sh - Функции валидации

# Проверить, запущено ли от root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        print_info "Use: sudo $0"
        exit 1
    fi
    print_debug "Running as root"
}

# Проверить доступность команды
command_exists() {
    local cmd=$1
    
    if command -v "$cmd" &> /dev/null; then
        print_debug "Command exists: $cmd"
        return 0
    else
        return 1
    fi
}

# Убедиться, что команда установлена
require_command() {
    local cmd=$1
    local package_name=${2:-$cmd}
    
    if ! command_exists "$cmd"; then
        print_error "Required command not found: $cmd"
        print_info "Install it with: apt-get install $package_name"
        return 1
    fi
    return 0
}

# Проверить интернет соединение
check_internet() {
    local retries=3
    local timeout=5
    
    print_debug "Checking internet connection..."
    
    for ((i=1; i<=retries; i++)); do
        if timeout $timeout ping -c 1 8.8.8.8 &> /dev/null; then
            print_debug "Internet connection OK"
            return 0
        fi
        print_debug "Connection attempt $i/$retries failed, retrying..."
    done
    
    return 1
}

# Проверить доступность порта
port_available() {
    local port=$1
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        return 1  # Порт занят
    fi
    return 0  # Порт свободен
}

# Убедиться что порт свободен
require_port() {
    local port=$1
    
    if ! port_available "$port"; then
        print_warning "Port $port is already in use"
        return 1
    fi
    print_debug "Port $port is available"
    return 0
}

# Валидировать IP адрес (IPv4)
validate_ipv4() {
    local ip=$1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Дополнительная проверка диапазона
        local IFS='.'
        read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Валидировать доменное имя
validate_domain() {
    local domain=$1
    
    # Простая регулярка для проверки домена
    if [[ $domain =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# Валидировать email
validate_email() {
    local email=$1
    
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# Валидировать URL
validate_url() {
    local url=$1
    
    if [[ $url =~ ^https?:// ]]; then
        return 0
    fi
    return 1
}

# Проверить файл существует
file_exists() {
    local file=$1
    
    if [[ -f "$file" ]]; then
        print_debug "File exists: $file"
        return 0
    fi
    return 1
}

# Проверить директория существует
directory_exists() {
    local dir=$1
    
    if [[ -d "$dir" ]]; then
        print_debug "Directory exists: $dir"
        return 0
    fi
    return 1
}

# Требовать файл
require_file() {
    local file=$1
    local description=${2:-$file}
    
    if ! file_exists "$file"; then
        print_error "Required file not found: $description"
        return 1
    fi
    return 0
}

# Требовать директорию
require_directory() {
    local dir=$1
    local description=${2:-$dir}
    
    if ! directory_exists "$dir"; then
        print_error "Required directory not found: $description"
        return 1
    fi
    return 0
}

# Получить публичный IP адрес
get_public_ip() {
    local ip
    
    # Пробуем несколько источников
    ip=$(curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null) && echo "$ip" && return 0
    ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null) && echo "$ip" && return 0
    ip=$(curl -s --connect-timeout 5 http://checkip.amazonaws.com 2>/dev/null | tr -d '\n') && echo "$ip" && return 0
    
    print_error "Failed to get public IP"
    return 1
}

# Проверить доступность домена (DNS)
domain_resolves() {
    local domain=$1
    
    if getent hosts "$domain" > /dev/null 2>&1; then
        print_debug "Domain resolves: $domain"
        return 0
    fi
    return 1
}

# Проверить можем ли записывать в директорию
test_write_permission() {
    local dir=$1
    local test_file="${dir}/.cascade-vpn-write-test"
    
    if ! mkdir -p "$dir" 2>/dev/null; then
        return 1
    fi
    
    if ! touch "$test_file" 2>/dev/null; then
        return 1
    fi
    
    rm -f "$test_file"
    return 0
}

# Проверить свободное место на диске (в MB)
check_disk_space() {
    local path=${1:-/}
    local required_mb=${2:-500}
    
    local available=$(df -BM "$path" | awk 'NR==2 {print $4}' | sed 's/M//')
    
    if ((available < required_mb)); then
        print_error "Insufficient disk space. Required: ${required_mb}MB, Available: ${available}MB"
        return 1
    fi
    
    print_debug "Disk space OK: ${available}MB available (required: ${required_mb}MB)"
    return 0
}
