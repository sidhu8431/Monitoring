#!/bin/bash

set -e
set -o pipefail

PROM_VERSION="3.4.0-rc.0"
PROM_USER="prometheus"
PROM_DIR="/opt/prometheus"
PROM_CONF_DIR="/etc/prometheus"
PROM_DATA_DIR="/var/lib/prometheus"
PROM_SERVICE_FILE="/etc/systemd/system/prometheus.service"
PROM_TGZ="prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_TGZ}"
TMP_EXTRACT_DIR="/tmp/prometheus_tmp"

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

check_installed() {
    if systemctl is-active --quiet prometheus; then
        echo "Prometheus is installed and running."
        version=$($PROM_DIR/prometheus --version 2>/dev/null | head -n1 || echo "unknown")
        echo "Installed version: $version"
        return 0
    elif [ -f "$PROM_DIR/prometheus" ]; then
        echo "Prometheus is installed but not running."
        version=$($PROM_DIR/prometheus --version 2>/dev/null | head -n1 || echo "unknown")
        echo "Installed version: $version"
        return 0
    else
        echo "Prometheus is not installed."
        return 1
    fi
}

install_prometheus() {
    if check_installed; then
        read -rp "Prometheus is already installed. Do you want to reinstall? [y/N]: " yn
        case "$yn" in
            [Yy]* ) echo "Proceeding with reinstall...";;
            * ) echo "Installation aborted."; exit 0;;
        esac
    fi

    echo "[*] Downloading Prometheus version $PROM_VERSION..."
    wget -q --show-progress "$PROM_URL" -O "/tmp/$PROM_TGZ"

    echo "[*] Preparing extraction directory $TMP_EXTRACT_DIR..."
    rm -rf "$TMP_EXTRACT_DIR"
    mkdir -p "$TMP_EXTRACT_DIR"

    echo "[*] Extracting Prometheus archive..."
    tar -zxvf "/tmp/$PROM_TGZ" -C "$TMP_EXTRACT_DIR"

    echo "[*] Moving Prometheus files to $PROM_DIR..."
    rm -rf "$PROM_DIR"
    mv "$TMP_EXTRACT_DIR/prometheus-${PROM_VERSION}.linux-amd64" "$PROM_DIR"

    echo "[*] Creating Prometheus user and directories..."
    id -u $PROM_USER &>/dev/null || useradd --no-create-home --shell /bin/false $PROM_USER
    mkdir -p "$PROM_CONF_DIR" "$PROM_DATA_DIR"

    echo "[*] Setting ownership for Prometheus directories..."
    chown -R $PROM_USER:$PROM_USER "$PROM_DIR" "$PROM_CONF_DIR" "$PROM_DATA_DIR"

    echo "[*] Writing prometheus.yml configuration..."
    cat > "$PROM_DIR/prometheus.yml" <<EOF
# Global configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets: []

# Load alerting or recording rules
rule_files: []

# Scrape configurations
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "ec2"
    ec2_sd_configs:
      - region: us-east-2
        port: 9100
        filters:
          - name: availability-zone
            values:
              - us-east-2a
    relabel_configs:
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      - source_labels: [__meta_ec2_private_ip]
        target_label: private_ip
      - source_labels: [__meta_ec2_tag_Name]
        target_label: name
EOF

    echo "[*] Setting ownership for prometheus.yml..."
    chown $PROM_USER:$PROM_USER "$PROM_DIR/prometheus.yml"

    echo "[*] Creating systemd service file..."
    cat > "$PROM_SERVICE_FILE" <<EOF
[Unit]
Description=Prometheus Server
Wants=network-online.target
After=network-online.target

[Service]
User=$PROM_USER
Group=$PROM_USER
Type=simple
ExecStart=$PROM_DIR/prometheus \\
  --config.file=$PROM_DIR/prometheus.yml \\
  --storage.tsdb.path=$PROM_DATA_DIR

[Install]
WantedBy=multi-user.target
EOF

    echo "[*] Reloading systemd daemon and starting Prometheus..."
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus

    echo "[*] Cleaning up temporary files..."
    rm -rf "$TMP_EXTRACT_DIR" "/tmp/$PROM_TGZ"

    echo "✅ Prometheus $PROM_VERSION installed and running!"
    echo "Check status: sudo systemctl status prometheus"
    echo "Prometheus UI: http://<your-server>:9090"
}

uninstall_prometheus() {
    if ! check_installed; then
        echo "Prometheus is not installed. Nothing to uninstall."
        exit 0
    fi

    echo "[*] Stopping and disabling Prometheus service..."
    systemctl stop prometheus || true
    systemctl disable prometheus || true

    echo "[*] Removing Prometheus files and user..."
    rm -rf "$PROM_DIR" "$PROM_CONF_DIR" "$PROM_DATA_DIR" "$PROM_SERVICE_FILE"

    if id "$PROM_USER" &>/dev/null; then
        userdel "$PROM_USER"
    fi

    systemctl daemon-reload
    echo "✅ Prometheus uninstalled."
}

echo "What do you want to do?"
echo "1) Install Prometheus"
echo "2) Uninstall Prometheus"
echo "3) Check Prometheus status and version"
read -rp "Enter choice [1-3]: " choice

case "$choice" in
    1) install_prometheus ;;
    2) uninstall_prometheus ;;
    3) check_installed ;;
    *) echo "Invalid choice. Exiting." ; exit 1 ;;
esac


# update the ec2 instance policy update
