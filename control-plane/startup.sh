#!/bin/bash
# Coder control plane bootstrap — runs on first boot via metadata_startup_script
set -euo pipefail

LOG="/var/log/coder-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== Coder bootstrap starting at $(date) ==="

# Install Coder
if ! command -v coder &>/dev/null; then
  echo "Installing Coder..."
  curl -fsSL https://coder.com/install.sh | sh
fi

# Create coder system user
if ! id coder &>/dev/null; then
  useradd -m -s /bin/bash coder
fi

# Coder data directory
mkdir -p /home/coder/.config/coderv2
chown -R coder:coder /home/coder/.config

# Determine version tag for logging
INSTALLED_VERSION=$(coder version 2>/dev/null || echo "unknown")
echo "Coder version: $INSTALLED_VERSION"

# Systemd service
cat > /etc/systemd/system/coder.service <<'EOF'
[Unit]
Description=Coder
After=network-online.target
Wants=network-online.target

[Service]
User=coder
ExecStart=/usr/bin/coder server
Environment=CODER_ACCESS_URL=http://localhost:3000
Environment=CODER_HTTP_ADDRESS=0.0.0.0:3000
Environment=CODER_TELEMETRY_ENABLE=false
# Lock down signups after first user
Environment=CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS=false
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now coder.service

echo "=== Coder bootstrap complete at $(date) ==="
echo "First user to sign up at http://localhost:3000 becomes the owner."
