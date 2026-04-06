#!/bin/bash
# Generate a Coder API token via SSH and login the local CLI.
# SSHes into the VM, creates a token using the coder CLI, pipes it back.
# Access is gated by IAP (requires admin_email) — no secrets stored anywhere.
# Requires: gcloud authenticated, coder CLI installed, IAP tunnel running (make connect).
set -euo pipefail

ZONE="us-central1-a"
INSTANCE="coder-server"
CODER_URL="http://localhost:3000"

export PATH="$HOME/.local/bin:$PATH"

echo "Generating API token via SSH..."
API_TOKEN=$(gcloud compute ssh "$INSTANCE" \
  --zone="$ZONE" \
  --tunnel-through-iap \
  --ssh-flag="-o StrictHostKeyChecking=no" \
  -- "sudo -u coder bash -c '
    # If the coder CLI is not yet logged in, login using the local server URL
    if ! coder tokens list &>/dev/null; then
      # Use the session token from bootstrap if available
      if [[ -f /home/coder/.config/coderv2/session ]]; then
        export CODER_SESSION_TOKEN=\$(cat /home/coder/.config/coderv2/session)
        export CODER_URL=http://localhost:3000
      fi
    fi
    coder tokens create --name cli-\$(date +%s) --lifetime 168h 2>/dev/null | tail -1
  '" 2>/dev/null | tr -d '[:space:]')

if [[ -z "$API_TOKEN" ]]; then
  echo "Failed to generate token. Is the VM running and Coder healthy?"
  echo "Try: make ssh, then: sudo -u coder coder tokens create"
  exit 1
fi

coder login "$CODER_URL" --token "$API_TOKEN"
echo "Logged in to Coder successfully."
