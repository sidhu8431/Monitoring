#!/bin/bash

# grafana-manager.sh
# Script to manage Grafana on Amazon Linux (Install, Uninstall, Version Check)

GRAFANA_VERSION="12.0.0"
GRAFANA_RPM_URL="https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}-1.x86_64.rpm"

# Ensure root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or using sudo."
  exit 1
fi

# Function to check Grafana version
check_grafana_version() {
  if command -v grafana-server &> /dev/null; then
    INSTALLED_VERSION=$(grafana-server -v | awk '{print $2}')
    echo "Grafana is installed. Version: $INSTALLED_VERSION"
  else
    echo "Grafana is not currently installed."
  fi
}

# Function to install Grafana
install_grafana() {
  if command -v grafana-server &> /dev/null; then
    INSTALLED_VERSION=$(grafana-server -v | awk '{print $2}')
    if [[ "$INSTALLED_VERSION" == "$GRAFANA_VERSION" ]]; then
      echo "Grafana $GRAFANA_VERSION is already installed."
      return
    else
      echo "A different version ($INSTALLED_VERSION) is installed. Installing $GRAFANA_VERSION..."
    fi
  else
    echo "Installing Grafana $GRAFANA_VERSION..."
  fi

  yum update -y
  yum install -y "$GRAFANA_RPM_URL"

  echo "Enabling and starting Grafana service..."
  systemctl enable grafana-server
  systemctl restart grafana-server

  if command -v firewall-cmd &> /dev/null; then
    echo "Opening port 3000 in the firewall..."
    firewall-cmd --zone=public --add-port=3000/tcp --permanent
    firewall-cmd --reload
  fi

  echo "Grafana $GRAFANA_VERSION installed and running!"
  echo "Access Grafana at: http://<your-ec2-public-ip>:3000"
  echo "Default login: admin / admin"
}

# Function to uninstall Grafana
uninstall_grafana() {
  if ! command -v grafana-server &> /dev/null; then
    echo "Grafana is not installed."
    return
  fi

  echo "Stopping Grafana service..."
  systemctl stop grafana-server

  echo "Uninstalling Grafana..."
  yum remove -y grafana

  echo "Grafana has been uninstalled."
}

# Main menu
while true; do
  echo ""
  echo "========== Grafana Manager =========="
  echo "1. Check Grafana Version"
  echo "2. Install Grafana $GRAFANA_VERSION"
  echo "3. Uninstall Grafana"
  echo "4. Exit"
  echo "====================================="
  read -rp "Choose an option [1-4]: " choice

  case $choice in
    1) check_grafana_version ;;
    2) install_grafana ;;
    3) uninstall_grafana ;;
    4) echo "Exiting..."; exit 0 ;;
    *) echo "Invalid choice. Please select a valid option." ;;
  esac
done
