#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

enable_firewall_ports() {
  echo "Configuring firewall rules..."

  # Check if firewalld is running
  if systemctl is-active --quiet firewalld; then
    echo "firewalld is running, adding ports..."

    # Open Filebeat default Logstash port 5044 TCP
    firewall-cmd --zone=public --add-port=5044/tcp --permanent
    # Open Elasticsearch HTTP port 9200 TCP (if needed)
    firewall-cmd --zone=public --add-port=9200/tcp --permanent
    # Open Kibana port 5601 TCP (if needed)
    firewall-cmd --zone=public --add-port=5601/tcp --permanent

    # Reload firewalld to apply changes
    firewall-cmd --reload

    echo "Firewall ports 5044, 9200, and 5601 opened."
  else
    echo "firewalld is not running or installed. Please configure your firewall manually."
  fi
}

install_filebeat() {
  echo "Updating packages and installing Filebeat..."
  yum update -y
  yum install filebeat -y

  echo "Backing up original filebeat.yml"
  cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak

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

  # Enable firewall ports after installation
  enable_firewall_ports

  echo "Installation and configuration completed."
  curl -XGET "localhost:9200/_cat/indices?v"
}

uninstall_filebeat() {
  echo "Stopping and disabling Filebeat service..."
  systemctl stop filebeat
  systemctl disable filebeat

  echo "Removing Filebeat package..."
  yum remove filebeat -y

  echo "Removing firewall rules for Filebeat ports..."
  if systemctl is-active --quiet firewalld; then
    firewall-cmd --zone=public --remove-port=5044/tcp --permanent
    firewall-cmd --zone=public --remove-port=9200/tcp --permanent
    firewall-cmd --zone=public --remove-port=5601/tcp --permanent
    firewall-cmd --reload
    echo "Firewall ports removed."
  else
    echo "firewalld not running. Please remove firewall rules manually if needed."
  fi

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
  1)
    install_filebeat
    ;;
  2)
    uninstall_filebeat
    ;;
  3)
    check_version
    ;;
  *)
    echo "Invalid choice. Please run the script again and select 1, 2, or 3."
    exit 1
    ;;
esac
