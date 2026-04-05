#!/usr/bin/env bash
# SSH into the Coder control plane via IAP.
# Usage: ./ssh.sh [--zone ZONE] [--instance NAME]
set -euo pipefail

ZONE="${CODER_ZONE:-us-central1-a}"
INSTANCE="${CODER_INSTANCE:-coder-server}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --zone) ZONE="$2"; shift 2 ;;
    --instance) INSTANCE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

gcloud compute ssh "$INSTANCE" --zone="$ZONE" --tunnel-through-iap -- "$@"
