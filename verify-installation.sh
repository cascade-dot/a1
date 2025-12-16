#!/bin/bash
# verify-installation.sh - Проверка что все файлы созданы

set -euo pipefail

echo "🔍 Проверка структуры проекта Cascade VPN Universal..."
echo ""

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_file() {
    local file=$1
    local description=$2
    
    if [[ -f "$file" ]]; then
        local size=$(wc -c < "$file")
        printf "${GREEN}✓${NC} %-50s (%s bytes)\n" "$description" "$size"
        return 0
    else
        printf "${RED}✗${NC} %s (NOT FOUND)\n" "$description"
        return 1
    fi
}

check_dir() {
    local dir=$1
    local description=$2
    
    if [[ -d "$dir" ]]; then
        printf "${GREEN}✓${NC} %s/\n" "$description"
        return 0
    else
        printf "${RED}✗${NC} %s/ (NOT FOUND)\n" "$description"
        return 1
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

total=0
success=0

# Утилиты
echo "📚 Утилиты (utils/):"
check_file "utils/colors.sh" "colors.sh" && ((success++)) || true
check_file "utils/logger.sh" "logger.sh" && ((success++)) || true
check_file "utils/validators.sh" "validators.sh" && ((success++)) || true
total=$((total + 3))
echo ""

# Core функции
echo "🔧 Основные функции (core/):"
check_file "core/prerequisites.sh" "prerequisites.sh" && ((success++)) || true
check_file "core/system-optimization.sh" "system-optimization.sh" && ((success++)) || true
total=$((total + 2))
echo ""

# Конфигурации
echo "⚙️ Конфигурации (configs/):"
check_file "configs/nginx/reverse-proxy.conf" "nginx/reverse-proxy.conf" && ((success++)) || true
check_file "configs/systemd/cascade-vpn.service" "systemd/cascade-vpn.service" && ((success++)) || true
check_file "configs/systemd/3x-ui.service" "systemd/3x-ui.service" && ((success++)) || true
check_file "configs/systemd/wg-easy.service" "systemd/wg-easy.service" && ((success++)) || true
check_file "configs/sysctl/cascade-vpn.conf" "sysctl/cascade-vpn.conf" && ((success++)) || true
total=$((total + 5))
echo ""

# Главные скрипты
echo "🚀 Главные управляющие скрипты:"
check_file "install.sh" "install.sh" && ((success++)) || true
check_file "update.sh" "update.sh" && ((success++)) || true
check_file "uninstall.sh" "uninstall.sh" && ((success++)) || true
total=$((total + 3))
echo ""

# Сервисы
echo "🌐 Сервисы VPN:"
check_file "services/v2ray/install.sh" "services/v2ray/install.sh" && ((success++)) || true
check_file "services/xray/install.sh" "services/xray/install.sh" && ((success++)) || true
total=$((total + 2))
echo ""

# Документация
echo "📖 Документация:"
check_file "INSTALL_GUIDE.md" "INSTALL_GUIDE.md" && ((success++)) || true
check_file "README_NEW.md" "README_NEW.md" && ((success++)) || true
check_file "DEVELOPMENT_REPORT.md" "DEVELOPMENT_REPORT.md" && ((success++)) || true
check_file "COMPLETION_SUMMARY.md" "COMPLETION_SUMMARY.md" && ((success++)) || true
check_file "QUICK_START.txt" "QUICK_START.txt" && ((success++)) || true
check_file "examples/cascade-vpn.conf.example" "examples/cascade-vpn.conf.example" && ((success++)) || true
total=$((total + 6))
echo ""

# Директории
echo "📁 Директории:"
check_dir "utils" "utils" && ((success++)) || true
check_dir "core" "core" && ((success++)) || true
check_dir "configs/nginx" "configs/nginx" && ((success++)) || true
check_dir "configs/systemd" "configs/systemd" && ((success++)) || true
check_dir "configs/sysctl" "configs/sysctl" && ((success++)) || true
total=$((total + 5))
echo ""

# Итого
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
percentage=$((success * 100 / total))
echo "Результат: ${GREEN}$success/$total${NC} файлов создано ($percentage%)"
echo ""

if [[ $success -eq $total ]]; then
    echo "${GREEN}✓ ВСЕ ФАЙЛЫ СОЗДАНЫ УСПЕШНО!${NC}"
    echo ""
    echo "Проект готов к использованию:"
    echo "  1. sudo bash install.sh        # Установка"
    echo "  2. sudo bash update.sh         # Обновление"
    echo "  3. sudo bash uninstall.sh      # Удаление"
    echo ""
    echo "Документация:"
    echo "  • QUICK_START.txt              # Быстрый старт"
    echo "  • INSTALL_GUIDE.md             # Полное руководство"
    echo "  • COMPLETION_SUMMARY.md        # Резюме разработки"
    echo ""
    exit 0
else
    echo "${RED}✗ Некоторые файлы отсутствуют!${NC}"
    exit 1
fi
