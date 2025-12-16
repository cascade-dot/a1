#!/bin/bash
# utils/logger.sh - Функции логирования

readonly LOG_DIR="/var/log/cascade-vpn"
readonly LOG_FILE="${LOG_DIR}/install.log"
readonly ERROR_LOG="${LOG_DIR}/error.log"

# Инициализация логирования
init_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE" "$ERROR_LOG"
    chmod 750 "$LOG_DIR"
    
    # Перенаправление вывода
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$ERROR_LOG" >&2)
}

# Получить временную метку
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Логировать сообщение
log_message() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(get_timestamp)
    
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

# Логировать с уровнем INFO
log_info() {
    log_message "INFO" "$@"
    print_info "$@"
}

# Логировать с уровнем SUCCESS
log_success() {
    log_message "SUCCESS" "$@"
    print_success "$@"
}

# Логировать с уровнем WARNING
log_warning() {
    log_message "WARNING" "$@"
    print_warning "$@"
}

# Логировать с уровнем ERROR
log_error() {
    log_message "ERROR" "$@"
    print_error "$@"
}

# Логировать DEBUG информацию
log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_message "DEBUG" "$@"
        print_debug "$@"
    fi
}

# Логировать исполнение команды
log_exec() {
    local cmd=$1
    log_debug "Executing: $cmd"
    
    if eval "$cmd"; then
        log_debug "Command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        log_error "Command failed with exit code $exit_code: $cmd"
        return "$exit_code"
    fi
}

# Начать секцию логирования
log_section_start() {
    local section=$1
    log_message "SECTION" "=== BEGIN: $section ==="
    print_subheader "Processing: $section"
}

# Завершить секцию логирования
log_section_end() {
    local section=$1
    local status=${2:-success}
    log_message "SECTION" "=== END: $section (Status: $status) ==="
}

# Экспортировать логи
export_logs() {
    local backup_path="${1:-.}/cascade-vpn-logs-$(date +%s).tar.gz"
    tar -czf "$backup_path" "$LOG_DIR"
    print_info "Logs exported to: $backup_path"
}

# Очистить логи (оставить последние N дней)
cleanup_logs() {
    local days=${1:-7}
    log_info "Cleaning logs older than $days days"
    
    find "$LOG_DIR" -type f -mtime +$days -delete
    log_success "Old logs cleaned"
}
