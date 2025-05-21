#!/bin/bash

# ELK Stack Management Script
# For Root or Sudo User Only
# Allows installation, uninstallation, or version checking of ELK Stack.

set -e

# Ensure the script is run as root or with sudo privileges
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo privileges. Exiting..."
  exit 1
fi

# Functions
install_elk() {
  echo "Installing ELK Stack..."
  echo "Updating the system..."
  yum update -y

  echo "Installing Java 11 Amazon Corretto..."
  rpm --import https://yum.corretto.aws/corretto.key
  curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
  yum install -y java-11-amazon-corretto
  java -version

  echo "Adding Elasticsearch GPG key and repository..."
  rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
  tee /etc/yum.repos.d/elasticsearch.repo <<EOF
[elasticsearch]
name=Elasticsearch repository
baseurl=https://artifacts.elastic.co/packages/8.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

  echo "Installing Elasticsearch..."
  yum install elasticsearch -y

  echo "Configuring Elasticsearch..."
  sed -i 's/#network.host: .*/network.host: 0.0.0.0/' /etc/elasticsearch/elasticsearch.yml
  sed -i 's/#discovery.seed_hosts: .*/discovery.seed_hosts: []/' /etc/elasticsearch/elasticsearch.yml
  sed -i '/xpack.security.enabled:/d' /etc/elasticsearch/elasticsearch.yml
  echo "xpack.security.enabled: false" >> /etc/elasticsearch/elasticsearch.yml

  echo "Starting and enabling Elasticsearch service..."
  systemctl enable elasticsearch
  systemctl start elasticsearch
  systemctl status elasticsearch

  echo "ELK installation completed successfully!"
}

uninstall_elk() {
  echo "Uninstalling ELK Stack..."
  echo "Stopping Elasticsearch service..."
  systemctl stop elasticsearch || true

  echo "Removing Elasticsearch..."
  yum remove elasticsearch -y

  echo "Cleaning up Elasticsearch configuration files..."
  rm -rf /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

  echo "Removing Java 11 Amazon Corretto..."
  yum remove java-11-amazon-corretto -y
  rm -f /etc/yum.repos.d/corretto.repo

  echo "Cleaning up Elasticsearch repository..."
  rm -f /etc/yum.repos.d/elasticsearch.repo

  echo "ELK uninstallation completed successfully!"
}

check_version() {
  echo "Checking ELK Stack Versions..."

  # Check Java version
  echo -e "\nJava Version:"
  java -version 2>&1 | grep "openjdk version" || echo "Java is not installed."

  # Check Elasticsearch version
  echo -e "\nElasticsearch Version:"
  if curl -s "http://localhost:9200" | grep -q '"version"'; then
    version=$(curl -s "http://localhost:9200" | grep -Po '"number"\s*:\s*"\K[0-9\.]+')
    if [[ -n $version ]]; then
      echo "Version: $version"
    else
      echo "Could not determine Elasticsearch version."
    fi
  else
    echo "Elasticsearch is not installed or not running."
  fi

  echo "Version check completed successfully!"
}

# Main Script
echo "Select an action for ELK Stack:"
echo "1. Install ELK Stack"
echo "2. Uninstall ELK Stack"
echo "3. Check Version of ELK Stack"
read -p "Enter your choice (1/2/3): " choice

case $choice in
  1)
    install_elk
    ;;
  2)
    uninstall_elk
    ;;
  3)
    check_version
    ;;
  *)
    echo "Invalid choice. Please run the script again."
    exit 1
    ;;
esac
