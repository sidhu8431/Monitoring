#!/bin/bash

# Check if the script is run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

LOGSTASH_CONF="/etc/logstash/conf.d/logstash.conf"

function install_logstash {
  echo "Installing Logstash..."
  sudo yum install logstash -y
  if [ $? -eq 0 ]; then
    echo "Logstash installed successfully."
    configure_logstash
    sudo systemctl enable logstash
    sudo systemctl start logstash
    sudo systemctl status logstash
  else
    echo "Failed to install Logstash."
    exit 1
  fi
}

function configure_logstash {
  echo "Configuring Logstash..."
  if [ ! -d "$(dirname "$LOGSTASH_CONF")" ]; then
    sudo mkdir -p "$(dirname "$LOGSTASH_CONF")"
  fi
  cat <<EOL | sudo tee "$LOGSTASH_CONF"
input {
  beats {
    port => 5044
  }
}
output {
  if [@metadata][pipeline] {
    elasticsearch {
      hosts => ["localhost:9200"]
      manage_template => false
      index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
      pipeline => "%{[@metadata][pipeline]}"
    }
  } else {
    elasticsearch {
      hosts => ["localhost:9200"]
      manage_template => false
      index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
    }
  }
}
EOL
  echo "Logstash configuration created at $LOGSTASH_CONF."
}

function uninstall_logstash {
  echo "Uninstalling Logstash..."
  sudo yum remove logstash -y
  if [ $? -eq 0 ]; then
    echo "Logstash uninstalled successfully."
  else
    echo "Failed to uninstall Logstash."
    exit 1
  fi
}

function check_version {
  echo "Checking Logstash version..."
  
  # Check if Logstash is in the system's PATH
  if command -v logstash &>/dev/null; then
    logstash --version
  else
    # Attempt to locate Logstash binary manually
    LOGSTASH_BIN=$(sudo find /usr/share/logstash/bin -type f -name "logstash" 2>/dev/null | head -n 1)
    
    if [ -n "$LOGSTASH_BIN" ]; then
      echo "Logstash binary found at: $LOGSTASH_BIN"
      $LOGSTASH_BIN --version
    else
      echo "Logstash is not installed or not found on this system."
    fi
  fi
}

# Menu
echo "Logstash Management Script"
echo "=========================="
echo "1. Install Logstash"
echo "2. Uninstall Logstash"
echo "3. Check Logstash Version"
read -p "Enter your choice (1-3): " choice

case $choice in
  1)
    install_logstash
    ;;
  2)
    uninstall_logstash
    ;;
  3)
    check_version
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac
