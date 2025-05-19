#!/bin/bash

# grafana-manager.sh - Manage Grafana on Amazon Linux

GRAFANA_VERSION="12.0.0"
GRAFANA_RPM_URL="https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}-1.x86_64.rpm"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root or use sudo."
  exit 1
fi

# Function to check Grafana version
check_grafana_version() {
  if command -v grafana-server &>/dev/null; then
    INSTALLED_VERSION=$(grafana-server -v | awk '{print $2}')
    echo "✅ Grafana is installed. Version: $INSTALLED_VERSION"
  else
    echo "❌ Grafana is not installed."
  fi
}

# Function to check if Grafana is listening on port 3000
check_grafana_port() {
  echo "🔍 Checking if Grafana is listening on port 3000..."
  if command -v netstat &>/dev/null; then
    netstat -nltp | grep ':3000' && echo "✅ Grafana is running on port 3000." || echo "❌ Port 3000 is not open. Grafana might not be running."
  else
    echo "⚠️ netstat not found. Install with: yum install -y net-tools"
  fi
}

# Function to install Grafana
install_grafana() {
  if command -v grafana-server &>/dev/null; then
    CURRENT_VERSION=$(grafana-server -v | awk '{print $2}')
    if [[ "$CURRENT_VERSION" == "$GRAFANA_VERSION" ]]; then
      echo "✅ Grafana version $GRAFANA_VERSION is already installed."
    else
      echo "⚠️ A different version ($CURRENT_VERSION) is installed. Reinstalling $GRAFANA_VERSION..."
    fi
  else
    echo "📦 Installing Grafana $GRAFANA_VERSION..."
  fi

  yum update -y
  yum install -y "$GRAFANA_RPM_URL"

  echo "🔄 Enabling and restarting Grafana..."
  systemctl enable grafana-server
  systemctl restart grafana-server

  if command -v firewall-cmd &>/dev/null; then
    echo "🔓 Opening port 3000 in the firewall..."
    firewall-cmd --zone=public --add-port=3000/tcp --permanent
    firewall-cmd --reload
  fi

  echo "✅ Grafana $GRAFANA_VERSION installed and running!"
  echo "🌐 Access at: http://<your-ec2-ip>:3000"
  echo "🔐 Default credentials: admin / admin"

  check_grafana_port
}

# Function to uninstall Grafana
uninstall_grafana() {
  if ! command -v grafana-server &>/dev/null; then
    echo "❌ Grafana is not installed."
    return
  fi

  echo "🛑 Stopping Grafana..."
  systemctl stop grafana-server

  echo "🧹 Removing Grafana..."
  yum remove -y grafana

  echo "✅ Grafana has been uninstalled."
}

# Prompt user for action
echo ""
echo "========== Grafana Manager =========="
echo "1️⃣  Install Grafana"
echo "2️⃣  Uninstall Grafana"
echo "3️⃣  Check Grafana Version"
echo "4️⃣  Exit"
echo "====================================="
read -rp "Choose an option [1-4]: " choice

case $choice in
  1) install_grafana ;;
  2) uninstall_grafana ;;
  3) check_grafana_version; check_grafana_port ;;
  4) echo "👋 Exiting..."; exit 0 ;;
  *) echo "❌ Invalid option. Please run the script again with a valid choice."; exit 1 ;;
esac

echo ""
echo "✅ Operation completed. Run the script again for another action."
