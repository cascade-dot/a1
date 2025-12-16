#!/bin/bash

# Cascade VPN Universal - Quick Install Script via curl
# GitHub: https://github.com/cascade-dot/a1

set -e

REPO_URL="https://raw.githubusercontent.com/cascade-dot/a1/main"
INSTALL_DIR="/opt/cascade-vpn"
REPO_NAME="cascade-vpn-a1"

echo "🚀 CASCADE VPN UNIVERSAL - УСТАНОВКА"
echo "====================================="
echo ""

# Проверка прав доступа
if [[ $EUID -ne 0 ]]; then
   echo "❌ Этот скрипт должен запускаться с правами root"
   echo "   Пожалуйста, используйте: sudo bash"
   exit 1
fi

# Проверка интернета
echo "📡 Проверка подключения к интернету..."
if ! ping -c 1 github.com &> /dev/null; then
    echo "❌ Нет доступа к интернету. Проверьте подключение."
    exit 1
fi

# Создание директории
echo "📁 Создание директории установки..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Скачивание основных файлов
echo "⬇️  Скачивание файлов..."

# Скачиваем основной скрипт установки
curl -sSL "$REPO_URL/install.sh" -o install.sh
chmod +x install.sh

# Скачиваем утилиты
mkdir -p utils
curl -sSL "$REPO_URL/utils/colors.sh" -o utils/colors.sh
curl -sSL "$REPO_URL/utils/logger.sh" -o utils/logger.sh
curl -sSL "$REPO_URL/utils/validators.sh" -o utils/validators.sh
chmod +x utils/*.sh

# Скачиваем core
mkdir -p core
curl -sSL "$REPO_URL/core/prerequisites.sh" -o core/prerequisites.sh
curl -sSL "$REPO_URL/core/system-optimization.sh" -o core/system-optimization.sh
chmod +x core/*.sh

# Скачиваем services
mkdir -p services/{openvpn,wireguard,v2ray,xray,3x-ui}
curl -sSL "$REPO_URL/services/openvpn/install.sh" -o services/openvpn/install.sh
curl -sSL "$REPO_URL/services/wireguard/install.sh" -o services/wireguard/install.sh
curl -sSL "$REPO_URL/services/v2ray/install.sh" -o services/v2ray/install.sh
curl -sSL "$REPO_URL/services/xray/install.sh" -o services/xray/install.sh
curl -sSL "$REPO_URL/services/3x-ui/install.sh" -o services/3x-ui/install.sh
chmod +x services/*/*.sh

# Скачиваем modules
mkdir -p modules/{certificates,clients,obfuscation,port-forwarding}
mkdir -p modules/certificates modules/clients modules/obfuscation modules/port-forwarding

# Скачиваем остальные скрипты
curl -sSL "$REPO_URL/update.sh" -o update.sh
curl -sSL "$REPO_URL/uninstall.sh" -o uninstall.sh
curl -sSL "$REPO_URL/verify-installation.sh" -o verify-installation.sh
chmod +x *.sh

echo ""
echo "✅ Все файлы скачаны в: $INSTALL_DIR"
echo ""
echo "🚀 НАЧАЛО УСТАНОВКИ"
echo "==================="
echo ""

# Запуск установщика
./install.sh

echo ""
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo ""
echo "📁 Директория установки: $INSTALL_DIR"
echo ""
echo "💡 Полезные команды:"
echo "   sudo bash $INSTALL_DIR/update.sh       # Обновление"
echo "   sudo bash $INSTALL_DIR/uninstall.sh    # Удаление"
echo "   bash $INSTALL_DIR/verify-installation.sh # Проверка"
echo ""
