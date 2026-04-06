#!/bin/bash
# Coder control plane bootstrap — runs on first boot via metadata_startup_script
set -euo pipefail

export HOME="$${HOME:-/root}"

LOG="/var/log/coder-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== Coder bootstrap starting at $(date) ==="

# Install Coder (pinned version if specified, otherwise latest)
DESIRED_VERSION="${coder_version}"
CURRENT_VERSION=$(coder version 2>/dev/null | head -1 | awk '{print $NF}' || echo "")
if ! command -v coder &>/dev/null || { [[ -n "$DESIRED_VERSION" ]] && [[ "$CURRENT_VERSION" != *"$DESIRED_VERSION"* ]]; }; then
  echo "Installing Coder $${DESIRED_VERSION:-latest}..."
  if [[ -n "$DESIRED_VERSION" ]]; then
    curl -fsSL https://coder.com/install.sh | sh -s -- --version "$DESIRED_VERSION"
  else
    curl -fsSL https://coder.com/install.sh | sh
  fi
fi

# Create coder system user
if ! id coder &>/dev/null; then
  useradd -m -s /bin/bash coder
fi

# --- Mount persistent data disk ---
DATA_DEVICE="/dev/disk/by-id/google-coder-data"
DATA_MOUNT="/home/coder/.config/coderv2"

mkdir -p "$DATA_MOUNT"

# Format on first use (no filesystem yet)
if ! blkid "$DATA_DEVICE" &>/dev/null; then
  echo "Formatting data disk..."
  mkfs.ext4 -m 0 -F "$DATA_DEVICE"
fi

# Mount if not already mounted
if ! mountpoint -q "$DATA_MOUNT"; then
  mount "$DATA_DEVICE" "$DATA_MOUNT"
fi

# Ensure fstab entry for persistence across reboots
if ! grep -q "google-coder-data" /etc/fstab; then
  echo "$DATA_DEVICE $DATA_MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

chown -R coder:coder "$DATA_MOUNT"

# Determine version tag for logging
INSTALLED_VERSION=$(coder version 2>/dev/null || echo "unknown")
echo "Coder version: $INSTALLED_VERSION"

# Determine internal IP for access URL (so workspace agents can reach us)
INTERNAL_IP=$(curl -sf -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
echo "Internal IP: $INTERNAL_IP"

# Systemd service
cat > /etc/systemd/system/coder.service <<EOF
[Unit]
Description=Coder
After=network-online.target
Wants=network-online.target

[Service]
User=coder
ExecStart=/usr/bin/coder server
Environment=CODER_ACCESS_URL=http://$INTERNAL_IP:3000
Environment=CODER_HTTP_ADDRESS=0.0.0.0:3000
Environment=CODER_TELEMETRY_ENABLE=false
Environment=CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS=true
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Add GitHub external auth if configured
%{ if github_oauth_client_id != "" ~}
mkdir -p /etc/systemd/system/coder.service.d
cat > /etc/systemd/system/coder.service.d/github-auth.conf <<'GHEOF'
[Service]
Environment=CODER_EXTERNAL_AUTH_0_ID=primary-github
Environment=CODER_EXTERNAL_AUTH_0_TYPE=github
Environment=CODER_EXTERNAL_AUTH_0_CLIENT_ID=${github_oauth_client_id}
Environment=CODER_EXTERNAL_AUTH_0_CLIENT_SECRET=${github_oauth_client_secret}
GHEOF
%{ endif ~}

systemctl daemon-reload
systemctl enable --now coder.service

# --- Auto-create first user ---
CODER_ADMIN_EMAIL="${coder_admin_email}"
CODER_ADMIN_PASSWORD="${coder_admin_password}"
CODER_URL="http://localhost:3000"

# Generate a password if none provided, persist it on the data disk
PASSWORD_FILE="/home/coder/.config/coderv2/.admin-password"
if [[ -z "$CODER_ADMIN_PASSWORD" ]]; then
  if [[ -f "$PASSWORD_FILE" ]]; then
    CODER_ADMIN_PASSWORD=$(cat "$PASSWORD_FILE")
  else
    CODER_ADMIN_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
    echo "$CODER_ADMIN_PASSWORD" > "$PASSWORD_FILE"
    chown coder:coder "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
  fi
fi

# Wait for Coder to be healthy
echo "Waiting for Coder to be ready..."
for i in $(seq 1 60); do
  if curl -sf "$CODER_URL/api/v2/buildinfo" &>/dev/null; then
    echo "Coder is ready"
    break
  fi
  if [[ $i -eq 60 ]]; then
    echo "ERROR: Coder did not become ready in 60s"
    exit 1
  fi
  sleep 1
done

# Create first user if not yet created (idempotent)
FIRST_USER_RESP=$(curl -sf "$CODER_URL/api/v2/users/first" 2>/dev/null || true)
if echo "$FIRST_USER_RESP" | grep -q "initial user has already been created"; then
  echo "First user already exists, skipping creation"
else
  echo "Creating first user..."
  curl -sf -X POST "$CODER_URL/api/v2/users/first" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$CODER_ADMIN_EMAIL\",\"username\":\"admin\",\"password\":\"$CODER_ADMIN_PASSWORD\"}" >/dev/null
  echo "First user created: $CODER_ADMIN_EMAIL"
fi

# Ensure the coder CLI is logged in (needed for `make login` to create tokens)
if [[ ! -f /home/coder/.config/coderv2/session ]]; then
  echo "Logging in coder CLI..."
  LOGIN_RESP=$(curl -sf -X POST "$CODER_URL/api/v2/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$CODER_ADMIN_EMAIL\",\"password\":\"$CODER_ADMIN_PASSWORD\"}" 2>/dev/null || true)
  SESSION_TOKEN=$(echo "$LOGIN_RESP" | grep -o '"session_token":"[^"]*"' | cut -d'"' -f4)
  if [[ -n "$SESSION_TOKEN" ]]; then
    echo "$SESSION_TOKEN" > /home/coder/.config/coderv2/session
    echo "$CODER_URL" > /home/coder/.config/coderv2/url
    chown coder:coder /home/coder/.config/coderv2/session /home/coder/.config/coderv2/url
    chmod 600 /home/coder/.config/coderv2/session
    echo "Coder CLI configured"
  else
    echo "WARNING: Could not login coder CLI (run 'make login' manually)"
  fi
fi

echo "=== Coder bootstrap complete at $(date) ==="
