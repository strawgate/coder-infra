#!/usr/bin/env bash
# Stop the Coder control plane VM (saves money when not in use).
set -euo pipefail

ZONE="${CODER_ZONE:-us-central1-a}"
INSTANCE="${CODER_INSTANCE:-coder-server}"

echo "Stopping ${INSTANCE} in ${ZONE}..."
gcloud compute instances stop "$INSTANCE" --zone="$ZONE"
echo "Done. VM is stopped (no compute charges while stopped; disk charges continue)."
