#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

FILEBEAT_PORTS=(5044 9200 5601)

remove_firewall_ports() {
  echo "Removing firewall ports if they exist..."

  if systemctl is-active --quiet firewalld; then
    for port in "${FILEBEAT_PORTS[@]}"; do
      if firewall-cmd --zone=public --list-ports | grep -qw "${port}/tcp"; then
        echo "Removing port ${port}/tcp from firewall..."
        firewall-cmd --zone=public --remove-port=${port}/tcp --permanent
      else
        echo "Port ${port}/tcp not present in firewall, skipping removal."
      fi
    done
    firewall-cmd --reload
    echo "Firewall ports removal done."
  else
    echo "firewalld is not running. Please remove firewall rules manually if needed."
  fi
}

enable_firewall_ports() {
  echo "Adding firewall ports if not already present..."

  if systemctl is-active --quiet firewalld; then
    for port in "${FILEBEAT_PORTS[@]}"; do
      if firewall-cmd --zone=public --list-ports | grep -qw "${port}/tcp"; then
        echo "Port ${port}/tcp already open, skipping."
      else
        echo "Adding port ${port}/tcp to firewall..."
        firewall-cmd --zone=public --add-port=${port}/tcp --permanent
      fi
    done
    firewall-cmd --reload
    echo "Firewall ports configured."
  else
    echo "firewalld is not running. Please configure your firewall manually if needed."
  fi
}

install_filebeat() {
  echo "Checking if Filebeat is already installed..."

  if rpm -q filebeat &>/dev/null; then
    echo "Filebeat is already installed."

    if systemctl is-active --quiet filebeat; then
      echo "Filebeat service is running."
    else
      echo "Filebeat service is not running. Starting Filebeat service..."
      systemctl start filebeat
    fi

    echo "Ensuring firewall ports are enabled..."
    enable_firewall_ports
  else
    echo "Filebeat not installed. Proceeding with installation..."

    # Remove ports first to avoid conflicts
    remove_firewall_ports

    echo "Updating packages and installing Filebeat..."
    yum update -y
    yum install filebeat -y

    echo "Backing up original filebeat.yml"
    if [ -f /etc/filebeat/filebeat.yml ]; then
      cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak
    fi

    echo "Writing default Filebeat configuration..."
    cat >/etc/filebeat/filebeat.yml <<'EOF'
filebeat.inputs:
- type: filestream
  id: my-filestream-id
  enabled: false
  paths:
    - /var/log/*.log

filebeat.config.modules:
  path: ${path.config}/modules.d/*.yml
  reload.enabled: false

setup.template.settings:
  index.number_of_shards: 1

output.logstash:
  hosts: ["localhost:5044"]

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
  - add_kubernetes_metadata: ~
EOF

    echo "Writing system module config..."
    cat >/etc/filebeat/modules.d/system.yml <<'EOF'
- module: system
  syslog:
    enabled: true
  auth:
    enabled: true
EOF

    echo "Enabling system module..."
    filebeat modules enable system

    echo "Setting up Filebeat pipelines and index management..."
    filebeat setup --pipelines --modules system
    filebeat setup --index-management -E output.logstash.enabled=false -E 'output.elasticsearch.hosts=["0.0.0.0:9200"]'
    filebeat setup -E output.logstash.enabled=false -E output.elasticsearch.hosts=['localhost:9200'] -E setup.kibana.host=localhost:5601

    echo "Starting and enabling Filebeat service..."
    systemctl start filebeat
    systemctl enable filebeat

    # Enable ports after install
    enable_firewall_ports

    echo "Installation and configuration completed."
    curl -XGET "localhost:9200/_cat/indices?v"
  fi
}

uninstall_filebeat() {
  echo "Stopping and disabling Filebeat service..."
  systemctl stop filebeat
  systemctl disable filebeat

  echo "Removing Filebeat package..."
  yum remove filebeat -y

  echo "Removing firewall rules for Filebeat ports..."
  remove_firewall_ports

  echo "Uninstallation completed."
}

check_version() {
  if command -v filebeat &>/dev/null; then
    filebeat version
  else
    echo "Filebeat is not installed."
  fi
}

echo "Select an option:"
echo "1) Install Filebeat"
echo "2) Uninstall Filebeat"
echo "3) Check Filebeat Version"
read -rp "Enter your choice [1-3]: " choice

case $choice in
  1) install_filebeat ;;
  2) uninstall_filebeat ;;
  3) check_version ;;
  *) echo "Invalid choice. Please run the script again and select 1, 2, or 3." ; exit 1 ;;
esac
