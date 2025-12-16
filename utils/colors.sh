#!/bin/bash
# utils/colors.sh - Функции для цветного вывода в консоль

# Цветовые коды ANSI
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'  # No Color

# Спецсимволы
readonly CHECK_MARK='✓'
readonly CROSS_MARK='✗'
readonly ARROW='→'
readonly WARN_MARK='⚠'

# Функции вывода с цветами
print_error() {
    echo -e "${RED}${CROSS_MARK} ERROR:${NC} $*" >&2
}

print_success() {
    echo -e "${GREEN}${CHECK_MARK} SUCCESS:${NC} $*"
}

print_info() {
    echo -e "${BLUE}${ARROW} INFO:${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}${WARN_MARK} WARNING:${NC} $*"
}

print_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${GRAY}[DEBUG] $*${NC}" >&2
    fi
}

# Подчеркивание и выделение
print_header() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_subheader() {
    echo -e "\n${PURPLE}>>> $*${NC}"
}

# Разделитель
print_separator() {
    echo -e "${GRAY}─────────────────────────────────────────────────${NC}"
}

# Форматированный вывод переменных
print_value() {
    local label=$1
    local value=$2
    printf "  ${CYAN}%-30s${NC} ${WHITE}%s${NC}\n" "$label:" "$value"
}
