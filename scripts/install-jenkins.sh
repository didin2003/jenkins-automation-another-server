#!/bin/bash

set -e
exec > >(tee -a /tmp/jenkins-install.log) 2>&1

echo "======================================"
echo " Jenkins Automated Installation"
echo "======================================"

PLUGINS_FILE="/tmp/jenkins-automation/jenkins/plugins.txt"
CASC_FILE="/tmp/jenkins-automation/jenkins/casc/jenkins.yaml"

echo ""
echo "[1/8] Validating configuration..."

: "${JENKINS_URL:?JENKINS_URL is not set}"
: "${JENKINS_ADMIN_USERNAME:?JENKINS_ADMIN_USERNAME is not set}"
: "${JENKINS_ADMIN_PASSWORD:?JENKINS_ADMIN_PASSWORD is not set}"
: "${JENKINS_ADMIN_NAME:?JENKINS_ADMIN_NAME is not set}"
: "${JENKINS_ADMIN_EMAIL:?JENKINS_ADMIN_EMAIL is not set}"

if [ ! -f "$PLUGINS_FILE" ]; then
    echo "ERROR: plugins.txt not found:"
    echo "$PLUGINS_FILE"
    exit 1
fi

if [ ! -f "$CASC_FILE" ]; then
    echo "ERROR: jenkins.yaml not found:"
    echo "$CASC_FILE"
    exit 1
fi

echo "Configuration validated."

echo ""
echo "[2/8] Disabling CD-ROM APT repository..."

if [ -f /etc/apt/sources.list ]; then
    sudo sed -i '/^[[:space:]]*deb .*file:\/\/\/cdrom/s/^/#/' \
        /etc/apt/sources.list
fi

echo ""
echo "[3/8] Updating packages..."

sudo apt-get update

echo ""
echo "[4/8] Installing prerequisites..."

sudo apt-get install -y \
    fontconfig \
    openjdk-21-jre \
    git \
    curl \
    wget

echo ""
echo "[5/8] Installing Jenkins..."

if [ -z "${JENKINS_VERSION:-}" ]; then
    echo "ERROR: JENKINS_VERSION is not set."
    exit 1
fi

echo "Requested Jenkins version: ${JENKINS_VERSION}"

if ! grep -q "pkg.jenkins.io/debian-stable" \
    /etc/apt/sources.list.d/jenkins.list 2>/dev/null; then

    echo "Adding Jenkins repository..."

    sudo mkdir -p /usr/share/keyrings

    sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
        https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
https://pkg.jenkins.io/debian-stable binary/" | \
        sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
fi

sudo apt-get update

CURRENT_VERSION=$(dpkg-query -W -f='${Version}' jenkins 2>/dev/null || true)

if [ "$CURRENT_VERSION" = "$JENKINS_VERSION" ]; then
    echo "Jenkins ${JENKINS_VERSION} is already installed."
else
    echo "Installing Jenkins version ${JENKINS_VERSION}..."
    sudo apt-get install -y "jenkins=${JENKINS_VERSION}"
fi

echo ""
echo "[6/8] Stopping Jenkins for configuration..."

sudo systemctl stop jenkins || true

echo ""
echo "[7/8] Installing Jenkins plugins..."

PLUGIN_MANAGER_VERSION="2.15.0"

PLUGIN_MANAGER_URL="https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${PLUGIN_MANAGER_VERSION}/jenkins-plugin-manager-${PLUGIN_MANAGER_VERSION}.jar"

PLUGIN_MANAGER="/tmp/jenkins-plugin-manager.jar"

if [ ! -f "$PLUGIN_MANAGER" ]; then
    echo "Downloading Jenkins Plugin Installation Manager..."
    wget -O "$PLUGIN_MANAGER" "$PLUGIN_MANAGER_URL"
fi

sudo java -jar "$PLUGIN_MANAGER" \
    --war /usr/share/java/jenkins.war \
    --plugin-file "$PLUGINS_FILE" \
    --plugin-download-directory /var/lib/jenkins/plugins

echo "Fixing Jenkins plugin permissions..."

sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins
sudo chmod -R u+rwX /var/lib/jenkins/plugins

echo ""
echo "[8/8] Configuring Jenkins with JCasC..."

sudo mkdir -p /var/lib/jenkins/casc

sudo cp "$CASC_FILE" \
    /var/lib/jenkins/casc/jenkins.yaml

sudo chown -R jenkins:jenkins /var/lib/jenkins/casc

echo ""
echo "Configuring Jenkins environment..."

sudo mkdir -p /etc/systemd/system/jenkins.service.d

sudo tee /etc/systemd/system/jenkins.service.d/automation.conf > /dev/null <<EOF
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc/jenkins.yaml"
Environment="JENKINS_URL=${JENKINS_URL}"
Environment="JENKINS_ADMIN_USERNAME=${JENKINS_ADMIN_USERNAME}"
Environment="JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD}"
Environment="JENKINS_ADMIN_NAME=${JENKINS_ADMIN_NAME}"
Environment="JENKINS_ADMIN_EMAIL=${JENKINS_ADMIN_EMAIL}"
Environment="JAVA_OPTS=-Djenkins.install.runSetupWizard=false"
EOF

sudo systemctl daemon-reload

echo ""
echo "Starting Jenkins..."

sudo systemctl enable jenkins
sudo systemctl restart jenkins

echo ""
echo "Waiting for Jenkins..."

for i in {1..30}; do

    if curl -fsS \
        --max-time 5 \
        "http://127.0.0.1:8080/login" \
        >/dev/null 2>&1; then

        echo "Jenkins is responding."

        break
    fi

    echo "Waiting for Jenkins... ($i/30)"
    sleep 2

done

echo ""
echo "======================================"
echo " Jenkins Automation Completed"
echo "======================================"

echo ""
echo "Jenkins URL:"
echo "$JENKINS_URL"

echo ""
echo "Admin username:"
echo "$JENKINS_ADMIN_USERNAME"

echo ""
echo "Checking Jenkins service..."

sudo systemctl --no-pager --full status jenkins
