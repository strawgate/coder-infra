#!/usr/bin/env bash
# Start the Coder control plane VM.
set -euo pipefail

ZONE="${CODER_ZONE:-us-central1-a}"
INSTANCE="${CODER_INSTANCE:-coder-server}"

echo "Starting ${INSTANCE} in ${ZONE}..."
gcloud compute instances start "$INSTANCE" --zone="$ZONE"
echo "Done. Run ./scripts/connect.sh to open the IAP tunnel."
