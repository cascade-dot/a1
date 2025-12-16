#!/bin/bash
# core/prerequisites.sh - Проверка и установка предусловий

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/colors.sh"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/validators.sh"

# Проверить и установить основные зависимости
setup_prerequisites() {
    log_section_start "System Prerequisites"
    
    # Проверка root
    check_root
    
    # Определяем ОС
    local os_type="unknown"
    if [[ -f /etc/debian_version ]]; then
        os_type="debian"
    elif [[ -f /etc/redhat-release ]]; then
        os_type="redhat"
    else
        print_error "Unsupported operating system"
        log_section_end "System Prerequisites" "failed"
        return 1
    fi
    
    print_info "Detected OS: $os_type"
    
    # Обновляем репозитории
    print_info "Updating package repositories..."
    if [[ "$os_type" == "debian" ]]; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq > /dev/null
    elif [[ "$os_type" == "redhat" ]]; then
        yum update -y -q > /dev/null
    fi
    
    log_success "Package repositories updated"
    
    # Обязательные команды
    local required_commands=(
        "curl:curl"
        "wget:wget"
        "tar:tar"
        "openssl:openssl"
        "systemctl:systemd"
        "ip:iproute2"
        "iptables:iptables"
        "netstat:net-tools"
        "dig:dnsutils"
    )
    
    print_info "Checking required commands..."
    local missing_packages=()
    
    for cmd_pair in "${required_commands[@]}"; do
        local cmd="${cmd_pair%%:*}"
        local package="${cmd_pair##*:}"
        
        if ! command_exists "$cmd"; then
            missing_packages+=("$package")
        else
            print_debug "✓ $cmd"
        fi
    done
    
    # Установить недостающие пакеты
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        print_info "Installing missing packages: ${missing_packages[*]}"
        
        if [[ "$os_type" == "debian" ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_packages[@]}" > /dev/null
        elif [[ "$os_type" == "redhat" ]]; then
            yum install -y "${missing_packages[@]}" > /dev/null
        fi
        
        log_success "Missing packages installed"
    else
        log_success "All required packages already installed"
    fi
    
    # Проверить интернет
    print_info "Checking internet connectivity..."
    if check_internet; then
        log_success "Internet connection OK"
    else
        print_error "No internet connection available"
        log_section_end "System Prerequisites" "failed"
        return 1
    fi
    
    # Проверить свободное место на диске (минимум 2GB)
    print_info "Checking disk space..."
    if check_disk_space "/" 2048; then
        log_success "Disk space check passed"
    else
        log_section_end "System Prerequisites" "failed"
        return 1
    fi
    
    log_section_end "System Prerequisites" "success"
    return 0
}

# Проверить версию bash
check_bash_version() {
    local required_version="4.0"
    local current_version="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    
    if (( ${BASH_VERSINFO[0]} < 4 )); then
        print_error "Bash 4.0 or later required. Current version: $current_version"
        return 1
    fi
    
    print_debug "Bash version: $current_version"
    return 0
}

# Создать рабочие директории
create_working_directories() {
    log_section_start "Creating Working Directories"
    
    local dirs=(
        "/opt/cascade-vpn"
        "/etc/cascade-vpn"
        "/var/log/cascade-vpn"
        "/var/lib/cascade-vpn"
    )
    
    for dir in "${dirs[@]}"; do
        if ! directory_exists "$dir"; then
            print_info "Creating directory: $dir"
            mkdir -p "$dir"
            chmod 750 "$dir"
        else
            print_debug "Directory already exists: $dir"
        fi
    done
    
    log_success "Working directories created"
    log_section_end "Creating Working Directories" "success"
}

# Проверить системные параметры
check_system_limits() {
    log_section_start "Checking System Limits"
    
    local max_open_files=$(ulimit -n)
    local min_required=65536
    
    if ((max_open_files < min_required)); then
        print_warning "Open file limit too low: $max_open_files (recommended: $min_required)"
        print_info "Consider increasing ulimit with: 'ulimit -n 65536'"
    else
        print_debug "Open file limit OK: $max_open_files"
    fi
    
    # Проверить максимальное количество процессов
    local max_processes=$(ulimit -u)
    print_debug "Max processes: $max_processes"
    
    log_section_end "Checking System Limits" "success"
}

# Установить переменные окружения
setup_environment_variables() {
    log_section_start "Setting Up Environment Variables"
    
    # Экспортируем переменные
    export CASCADE_VPN_HOME="/opt/cascade-vpn"
    export CASCADE_VPN_CONFIG="/etc/cascade-vpn"
    export CASCADE_VPN_LOGS="/var/log/cascade-vpn"
    export CASCADE_VPN_DATA="/var/lib/cascade-vpn"
    export CASCADE_VPN_VERSION="1.0.0"
    
    # Проверяем можем ли записывать в директории
    for dir in "$CASCADE_VPN_CONFIG" "$CASCADE_VPN_LOGS" "$CASCADE_VPN_DATA"; do
        if ! test_write_permission "$dir"; then
            print_error "No write permission in: $dir"
            log_section_end "Setting Up Environment Variables" "failed"
            return 1
        fi
    done
    
    log_success "Environment variables configured"
    log_section_end "Setting Up Environment Variables" "success"
}

# Основная функция
main() {
    print_header "CASCADE VPN - Prerequisites Setup"
    
    if ! check_bash_version; then
        return 1
    fi
    
    if ! setup_prerequisites; then
        return 1
    fi
    
    if ! create_working_directories; then
        return 1
    fi
    
    check_system_limits
    
    if ! setup_environment_variables; then
        return 1
    fi
    
    print_header "Prerequisites Check Completed Successfully"
    return 0
}

# Исполнить если запущено как скрипт
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
