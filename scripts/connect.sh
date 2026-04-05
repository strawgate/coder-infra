#!/usr/bin/env bash
# Connect to the Coder control plane via IAP tunnel.
# Usage: ./connect.sh [--zone ZONE] [--instance NAME]
set -euo pipefail

ZONE="${CODER_ZONE:-us-central1-a}"
INSTANCE="${CODER_INSTANCE:-coder-server}"
LOCAL_PORT="${CODER_LOCAL_PORT:-3000}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --zone) ZONE="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    --port) LOCAL_PORT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "Opening IAP tunnel to ${INSTANCE} in ${ZONE}..."
echo "Coder will be available at http://localhost:${LOCAL_PORT}"
echo "Press Ctrl+C to disconnect."
echo ""

gcloud compute start-iap-tunnel "$INSTANCE" 3000 \
  --local-host-port="localhost:${LOCAL_PORT}" \
  --zone="$ZONE"
