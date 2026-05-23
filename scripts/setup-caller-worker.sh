#!/bin/bash
set -e
exec > /var/log/iii-caller-worker.log 2>&1

# Read engine IP from GCP instance metadata
ENGINE_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/engine-ip" -H "Metadata-Flavor: Google")

echo "=== Starting caller worker setup, engine at $ENGINE_IP ==="

apt-get update -y
apt-get install -y curl git netcat-openbsd

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install iii
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# Clone the project
git clone https://github.com/Alchemyst-ai/hiring.git /opt/iii-project

# Install TypeScript dependencies
cd /opt/iii-project/may-2026/devops/quickstart/workers/caller-worker
npm install

# Wait for engine
echo "Waiting for engine at $ENGINE_IP:49134..."
until nc -z "$ENGINE_IP" 49134; do
  echo "Engine not ready, retrying in 10s..."
  sleep 10
done
echo "Engine is up!"

# Create systemd service
cat > /etc/systemd/system/caller-worker.service << SERVICEEOF
[Unit]
Description=iii Caller Worker (TypeScript)
After=network.target

[Service]
User=root
WorkingDirectory=/opt/iii-project/may-2026/devops/quickstart/workers/caller-worker
ExecStart=npm start
Restart=always
RestartSec=10
Environment=PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
Environment=III_URL=ws://$ENGINE_IP:49134

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable caller-worker
systemctl start caller-worker

echo "=== Caller worker setup complete ==="
