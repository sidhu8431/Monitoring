#!/bin/bash

# Check if the script is run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

KIBANA_CONF="/etc/kibana/kibana.yml"

function install_kibana {
  echo "Installing Kibana..."
  sudo yum install kibana -y
  if [ $? -eq 0 ]; then
    echo "Kibana installed successfully."
    configure_kibana
    sudo systemctl enable kibana
    sudo systemctl start kibana
    sudo systemctl status kibana
  else
    echo "Failed to install Kibana."
    exit 1
  fi
}

function configure_kibana {
  echo "Configuring Kibana..."
  cat <<EOL | sudo tee "$KIBANA_CONF"
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
EOL
  echo "Kibana configuration updated at $KIBANA_CONF."
  sudo systemctl restart kibana
}

function uninstall_kibana {
  echo "Uninstalling Kibana..."
  sudo yum remove kibana -y
  if [ $? -eq 0 ]; then
    echo "Kibana uninstalled successfully."
  else
    echo "Failed to uninstall Kibana."
    exit 1
  fi
}

function check_version {
  echo "Checking Kibana version..."
  
  # Check if Kibana is in the system's PATH
  if command -v kibana &>/dev/null; then
    kibana --version
  else
    # Attempt to locate Kibana binary manually
    KIBANA_BIN=$(sudo find /usr/share/kibana/bin -type f -name "kibana" 2>/dev/null | head -n 1)
    
    if [ -n "$KIBANA_BIN" ]; then
      echo "Kibana binary found at: $KIBANA_BIN"
      $KIBANA_BIN --version
    else
      echo "Kibana is not installed or not found on this system."
    fi
  fi
}

# Menu
echo "Kibana Management Script"
echo "========================="
echo "1. Install Kibana"
echo "2. Uninstall Kibana"
echo "3. Check Kibana Version"
read -p "Enter your choice (1-3): " choice

case $choice in
  1)
    install_kibana
    ;;
  2)
    uninstall_kibana
    ;;
  3)
    check_version
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac
