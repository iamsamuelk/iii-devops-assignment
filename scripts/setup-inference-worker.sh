#!/bin/bash
set -e
exec > /var/log/iii-inference-worker.log 2>&1

# Read engine IP from GCP instance metadata
ENGINE_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/engine-ip" -H "Metadata-Flavor: Google")

echo "=== Starting inference worker setup, engine at $ENGINE_IP ==="

apt-get update -y
apt-get install -y curl git python3 python3-pip python3-venv netcat-openbsd

# Install iii
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# Clone the project
git clone https://github.com/Alchemyst-ai/hiring.git /opt/iii-project

# Install Python dependencies
cd /opt/iii-project/may-2026/devops/quickstart/workers/inference-worker
pip3 install --break-system-packages -r requirements.txt

# Wait for engine to be reachable
echo "Waiting for engine at $ENGINE_IP:49134..."
until nc -z "$ENGINE_IP" 49134; do
  echo "Engine not ready, retrying in 10s..."
  sleep 10
done
echo "Engine is up!"

# Create systemd service
cat > /etc/systemd/system/inference-worker.service << SERVICEEOF
[Unit]
Description=iii Inference Worker (Python)
After=network.target

[Service]
User=root
WorkingDirectory=/opt/iii-project/may-2026/devops/quickstart/workers/inference-worker
ExecStart=python3 inference_worker.py
Restart=always
RestartSec=10
Environment=PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
Environment=III_URL=ws://$ENGINE_IP:49134

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable inference-worker
systemctl start inference-worker

echo "=== Inference worker setup complete ==="
