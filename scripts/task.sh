#!/bin/bash
# Launch a Coder task with an optional prompt file.
#
# Usage:
#   scripts/task.sh [--ttl DURATION] [--preset PRESET] [--template TEMPLATE] [--name NAME] [--prompt-file FILE] PROMPT
#
# The prompt file content is prepended to the PROMPT argument.
#
# Examples:
#   scripts/task.sh --preset "logfwd / memagent" "PR Nurse PR #1320"
#   scripts/task.sh --prompt-file prompts/pr-nurse.md --preset "logfwd / memagent" "PR #1320 on strawgate/memagent"
#   scripts/task.sh --ttl 30m "Bug Hunt on strawgate/memagent"
#
# Requires: coder CLI authenticated, IAP tunnel running (make connect)

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

TTL=""
PRESET=""
TEMPLATE="gcp-agent"
NAME=""
PROMPT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ttl)         TTL="$2"; shift 2 ;;
    --preset)      PRESET="$2"; shift 2 ;;
    --template)    TEMPLATE="$2"; shift 2 ;;
    --name)        NAME="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    *)             break ;;
  esac
done

INLINE_PROMPT="${*:-}"

# Build the full prompt: file contents + inline prompt
PROMPT=""
if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: prompt file not found: $PROMPT_FILE" >&2
    exit 1
  fi
  PROMPT=$(cat "$PROMPT_FILE")
fi

if [[ -n "$INLINE_PROMPT" ]]; then
  if [[ -n "$PROMPT" ]]; then
    PROMPT="$PROMPT"$'\n\n'"$INLINE_PROMPT"
  else
    PROMPT="$INLINE_PROMPT"
  fi
fi

if [[ -z "$PROMPT" ]]; then
  echo "Error: no prompt provided (use --prompt-file and/or positional args)" >&2
  exit 1
fi

# Build the create command
CMD=(coder tasks create --template "$TEMPLATE" --quiet)
[[ -n "$PRESET" ]] && CMD+=(--preset "$PRESET")
[[ -n "$NAME" ]]   && CMD+=(--name "$NAME")
CMD+=("$PROMPT")

echo "Creating task..."
TASK_ID=$("${CMD[@]}")
echo "Task created: $TASK_ID"

# Set per-workspace autostop if TTL provided
if [[ -n "$TTL" ]]; then
  # Task ID is workspace name — set its stop schedule
  WORKSPACE=$(coder tasks list --output json 2>/dev/null \
    | jq -r ".[] | select(.id == \"$TASK_ID\") | .workspace_name // empty" 2>/dev/null || true)

  if [[ -z "$WORKSPACE" ]]; then
    # Fallback: the task name IS the workspace name in most cases
    WORKSPACE="$TASK_ID"
  fi

  echo "Setting TTL to $TTL for workspace $WORKSPACE..."
  coder schedule stop "$WORKSPACE" "$TTL" 2>/dev/null || \
    echo "Warning: could not set TTL (workspace may not be ready yet)"
fi

echo "Done. View at: $(coder url 2>/dev/null || echo 'http://localhost:3000')"
