#!/bin/bash

# Cascade VPN Universal - Curl Installer
# GitHub: https://github.com/cascade-dot/a1

set -e

REPO_URL="https://raw.githubusercontent.com/cascade-dot/a1/main"
INSTALL_DIR="/opt/cascade-vpn"

echo "🚀 CASCADE VPN UNIVERSAL - БЫСТРАЯ УСТАНОВКА"
echo "============================================"
echo ""

# Проверка прав доступа
if [[ $EUID -ne 0 ]]; then
   echo "❌ Необходимы права root!"
   echo "   Запустите: sudo bash"
   exit 1
fi

# Проверка curl
if ! command -v curl &> /dev/null; then
    echo "❌ curl не установлен. Установите: apt-get install curl"
    exit 1
fi

# Создание директории
echo "📁 Создание директории $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Функция для скачивания
download_file() {
    local url="$1"
    local dest="$2"
    local dirname=$(dirname "$dest")
    mkdir -p "$dirname"
    
    echo "⬇️  Скачивание $dest..."
    curl -sSL "$url" -o "$dest" 2>/dev/null || {
        echo "⚠️  Не удалось скачать: $url (возможно, файл не существует)"
        return 1
    }
    chmod +x "$dest" 2>/dev/null || true
}

# Скачиваем основные файлы
echo ""
echo "⬇️  Скачивание файлов из GitHub..."

# Основной скрипт
download_file "$REPO_URL/install.sh" "./install.sh"

# Утилиты
download_file "$REPO_URL/utils/colors.sh" "./utils/colors.sh"
download_file "$REPO_URL/utils/logger.sh" "./utils/logger.sh"
download_file "$REPO_URL/utils/validators.sh" "./utils/validators.sh"

# Core скрипты
download_file "$REPO_URL/core/prerequisites.sh" "./core/prerequisites.sh"
download_file "$REPO_URL/core/system-optimization.sh" "./core/system-optimization.sh"

# Services
download_file "$REPO_URL/services/openvpn/install.sh" "./services/openvpn/install.sh"
download_file "$REPO_URL/services/wireguard/install.sh" "./services/wireguard/install.sh"
download_file "$REPO_URL/services/v2ray/install.sh" "./services/v2ray/install.sh"
download_file "$REPO_URL/services/xray/install.sh" "./services/xray/install.sh"
download_file "$REPO_URL/services/3x-ui/install.sh" "./services/3x-ui/install.sh"

# Остальные скрипты
download_file "$REPO_URL/update.sh" "./update.sh"
download_file "$REPO_URL/uninstall.sh" "./uninstall.sh"
download_file "$REPO_URL/verify-installation.sh" "./verify-installation.sh"

# Конфиги
mkdir -p configs/{nginx,systemd,sysctl}
download_file "$REPO_URL/configs/systemd/cascade-vpn.service" "./configs/systemd/cascade-vpn.service"
download_file "$REPO_URL/configs/systemd/openvpn.service" "./configs/systemd/openvpn.service"

echo ""
echo "✅ Файлы скачаны в: $INSTALL_DIR"
echo ""

# Запуск установщика
if [ -f "$INSTALL_DIR/install.sh" ]; then
    echo "🚀 Запуск установщика..."
    echo "======================="
    echo ""
    bash "$INSTALL_DIR/install.sh"
else
    echo "❌ Ошибка: install.sh не был скачан"
    echo ""
    echo "💡 Попробуйте вручную:"
    echo "   cd $INSTALL_DIR"
    echo "   bash install.sh"
    exit 1
fi

echo ""
echo "✅ ГОТОВО!"
echo ""
echo "📁 Установка в: $INSTALL_DIR"
echo ""
echo "💡 Команды управления:"
echo "   sudo bash $INSTALL_DIR/update.sh"
echo "   sudo bash $INSTALL_DIR/uninstall.sh"
echo ""
