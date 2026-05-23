#!/bin/bash
set -e
exec > /var/log/iii-setup.log 2>&1

echo "=== Starting gateway setup ==="

apt-get update -y
apt-get install -y curl git

# Install iii
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# Clone the project
git clone https://github.com/Alchemyst-ai/hiring.git /opt/iii-project

# Write the gateway config (no worker_path entries, host 0.0.0.0)
cat > /opt/iii-project/may-2026/devops/quickstart/config.yaml << 'CONFIGEOF'
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii
      exporter: memory
      memory_max_spans: 10000
      metrics_enabled: true
      metrics_exporter: memory
      logs_enabled: true
      logs_exporter: memory
      logs_console_output: true
      sampling_ratio: 1.0
  - name: iii-queue
    config:
      adapter:
        name: builtin
  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: ./data/state_store.db
  - name: iii-http
    config:
      port: 3111
      host: 0.0.0.0
      default_timeout: 30000
      concurrency_request_limit: 1024
      cors:
        allowed_origins:
        - '*'
        allowed_methods:
        - GET
        - POST
        - PUT
        - DELETE
        - OPTIONS
CONFIGEOF

# Create systemd service for the engine
cat > /etc/systemd/system/iii-engine.service << 'SERVICEEOF'
[Unit]
Description=iii Engine
After=network.target

[Service]
User=root
WorkingDirectory=/opt/iii-project/may-2026/devops/quickstart
ExecStart=/root/.local/bin/iii --config config.yaml
Restart=always
RestartSec=5
Environment=PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable iii-engine
systemctl start iii-engine

echo "=== Gateway setup complete ==="
