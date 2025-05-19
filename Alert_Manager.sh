#!/bin/bash

set -e

ALERTMANAGER_VERSION="0.28.1"
INSTALL_DIR="/opt/alertmanager"
SERVICE_FILE="/etc/systemd/system/alertmanager.service"
CONFIG_FILE="${INSTALL_DIR}/alertmanager.yml"
USER="alertmanager"
TARBALL="alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

# Ensure script is run as root
require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "❌ This script must be run as root or with sudo."
    exit 1
  fi
}

# Install Alertmanager
install_alertmanager() {
  echo "📦 Installing Alertmanager v${ALERTMANAGER_VERSION}..."

  wget -q https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/${TARBALL}
  tar -zxvf ${TARBALL}
  rm -f ${TARBALL}  # Remove tarball after extraction

  mv alertmanager-${ALERTMANAGER_VERSION}.linux-amd64 ${INSTALL_DIR}

  useradd --no-create-home --shell /bin/false ${USER} 2>/dev/null || true

  mkdir -p /etc/alertmanager /var/lib/alertmanager
  chown -R ${USER}:${USER} ${INSTALL_DIR} /etc/alertmanager /var/lib/alertmanager

  cat <<EOF > ${CONFIG_FILE}
global:
  resolve_timeout: 5m

route:
  receiver: 'default'

receivers:
  - name: 'default'
EOF

  chown ${USER}:${USER} ${CONFIG_FILE}

  cat <<EOF > ${SERVICE_FILE}
[Unit]
Description=Alertmanager Service
Wants=network-online.target
After=network-online.target

[Service]
User=${USER}
Group=${USER}
Type=simple
ExecStart=${INSTALL_DIR}/alertmanager \\
  --config.file=${CONFIG_FILE} \\
  --storage.path=/var/lib/alertmanager

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now alertmanager

  echo "✅ Alertmanager installed and running on port 9093"
  systemctl status alertmanager --no-pager
}

# Uninstall Alertmanager
uninstall_alertmanager() {
  echo "🧹 Uninstalling Alertmanager..."
  systemctl stop alertmanager || true
  systemctl disable alertmanager || true
  rm -f ${SERVICE_FILE}
  systemctl daemon-reload
  rm -rf ${INSTALL_DIR} /etc/alertmanager /var/lib/alertmanager
  userdel ${USER} 2>/dev/null || true
  echo "✅ Alertmanager uninstalled"
}

# Check installed version
check_version() {
  if [[ -f "${INSTALL_DIR}/alertmanager" ]]; then
    VERSION=$(${INSTALL_DIR}/alertmanager --version | head -n 1)
    echo "🔎 Installed Alertmanager version: ${VERSION}"
  else
    echo "ℹ️ Alertmanager is not installed."
  fi
}

# Main menu
require_root
echo "===== Alertmanager Setup Script ====="
echo "1) Install Alertmanager"
echo "2) Uninstall Alertmanager"
echo "3) Check Installed Version"
read -rp "Enter choice [1-3]: " CHOICE

case "$CHOICE" in
  1) install_alertmanager ;;
  2) uninstall_alertmanager ;;
  3) check_version ;;
  *) echo "❌ Invalid choice"; exit 1 ;;
esac
