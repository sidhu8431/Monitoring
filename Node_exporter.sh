#!/bin/bash

set -e
set -o pipefail

NODE_EXPORTER_VERSION="1.9.1"
NODE_EXPORTER_DIR="/opt/node_exporter"
NODE_EXPORTER_BINARY="${NODE_EXPORTER_DIR}/node_exporter"
SERVICE_FILE="/etc/systemd/system/node_exporter.service"

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root or using sudo."
    exit 1
fi

install_node_exporter() {
    echo "📥 Installing Node Exporter v${NODE_EXPORTER_VERSION}..."

    echo "[*] Creating directory..."
    mkdir -p ${NODE_EXPORTER_DIR}

    echo "[*] Downloading and extracting Node Exporter..."
    cd /tmp
    wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
    tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

    echo "[*] Moving binary to ${NODE_EXPORTER_BINARY}..."
    mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter ${NODE_EXPORTER_BINARY}
    chmod +x ${NODE_EXPORTER_BINARY}

    echo "[*] Cleaning up..."
    rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*
    
    echo "[*] Creating systemd service file..."
    cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=${NODE_EXPORTER_BINARY}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    echo "[*] Reloading systemd and starting Node Exporter..."
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl restart node_exporter

    echo "✅ Node Exporter installed, enabled, and started successfully."
    systemctl status node_exporter --no-pager
}

uninstall_node_exporter() {
    echo "🗑️ Uninstalling Node Exporter..."

    systemctl stop node_exporter || true
    systemctl disable node_exporter || true
    rm -f ${SERVICE_FILE}
    rm -rf ${NODE_EXPORTER_DIR}

    systemctl daemon-reload

    echo "✅ Node Exporter uninstalled successfully."
}

check_node_exporter_version() {
    if [[ -x ${NODE_EXPORTER_BINARY} ]]; then
        echo -n "🔍 Node Exporter version: "
        ${NODE_EXPORTER_BINARY} --version
    else
        echo "⚠️ Node Exporter is not installed."
    fi
}

echo "=== Node Exporter Manager ==="
echo "1) Install Node Exporter"
echo "2) Uninstall Node Exporter"
echo "3) Check Node Exporter Version"
echo "4) Exit"

read -p "Choose an option [1-4]: " choice

case $choice in
    1) install_node_exporter ;;
    2) uninstall_node_exporter ;;
    3) check_node_exporter_version ;;
    4) echo "👋 Exiting..."; exit 0 ;;
    *) echo "❌ Invalid option." ; exit 1 ;;
esac
