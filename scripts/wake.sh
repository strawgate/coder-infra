#!/bin/bash
# Wake a paused task and optionally send it a follow-up message.
#
# Usage:
#   scripts/wake.sh TASK_NAME [MESSAGE]
#   scripts/wake.sh TASK_NAME --prompt-file FILE [MESSAGE]
#
# If the task is already running, just sends the message.
# If no message is provided, resumes with a default "check on things" prompt.
#
# Examples:
#   scripts/wake.sh pr-nurse-pr-1320-on-ac33
#   scripts/wake.sh pr-nurse-pr-1320-on-ac33 "CI failed again, please check"
#   scripts/wake.sh pr-nurse-pr-1320-on-ac33 "Check on the PR — any new reviews or CI changes?"
#
# Requires: coder CLI authenticated, IAP tunnel running (make connect)

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

PROMPT_FILE=""
TASK_NAME=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    *)
      if [[ -z "$TASK_NAME" ]]; then
        TASK_NAME="$1"; shift
      else
        break
      fi
      ;;
  esac
done

if [[ -z "$TASK_NAME" ]]; then
  echo "Usage: scripts/wake.sh TASK_NAME [MESSAGE]" >&2
  exit 1
fi

INLINE_MSG="${*:-}"

# Build message
MSG=""
if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: prompt file not found: $PROMPT_FILE" >&2
    exit 1
  fi
  MSG=$(cat "$PROMPT_FILE")
fi
if [[ -n "$INLINE_MSG" ]]; then
  [[ -n "$MSG" ]] && MSG="$MSG"$'\n\n'"$INLINE_MSG" || MSG="$INLINE_MSG"
fi
if [[ -z "$MSG" ]]; then
  MSG="Check on the PR — look for new reviews, CI status changes, or merge conflicts. Address anything new, then report what you found."
fi

# Check task status
echo "Checking task: $TASK_NAME"
STATUS=$(coder tasks status "$TASK_NAME" --output json 2>/dev/null \
  | jq -r '.status // .state // "unknown"' 2>/dev/null || echo "unknown")
echo "Status: $STATUS"

case "$STATUS" in
  stopped|paused|suspended)
    echo "Resuming task..."
    coder tasks resume "$TASK_NAME" --yes --no-wait
    echo "Waiting for task to be ready..."
    sleep 10
    ;;
  running|starting)
    echo "Task already running."
    ;;
  *)
    echo "Task status is '$STATUS' — attempting resume..."
    coder tasks resume "$TASK_NAME" --yes --no-wait 2>/dev/null || true
    sleep 10
    ;;
esac

echo "Sending message..."
coder tasks send "$TASK_NAME" "$MSG"
echo "Done."
