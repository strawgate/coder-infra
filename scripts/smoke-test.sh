#!/usr/bin/env bash
# Smoke test: creates a task, waits for agent health + response, cleans up.
# Usage: ./scripts/smoke-test.sh [--template NAME]
set -euo pipefail

TEMPLATE="${CODER_TASK_TEMPLATE_NAME:-gcp-agent}"
TASK_NAME="smoke-test-$(date +%s)"
TIMEOUT_SECONDS="${SMOKE_TEST_TIMEOUT:-600}"
POLL_INTERVAL=15

# Load .env for github_token if present
if [[ -f "$(git rev-parse --show-toplevel 2>/dev/null)/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$(git rev-parse --show-toplevel)/.env"
  set +a
fi

cleanup() {
  echo "--- Cleaning up task ${TASK_NAME} ---"
  coder tasks delete "${TASK_NAME}" --yes 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Coder Deployment Smoke Test ==="
echo "Template: ${TEMPLATE}"
echo "Task:     ${TASK_NAME}"
echo "Timeout:  ${TIMEOUT_SECONDS}s"
echo ""

# --- Create the task ---
echo "--- Creating task ---"
TASK_ID=$(coder tasks create \
  --template "${TEMPLATE}" \
  --name "${TASK_NAME}" \
  --quiet \
  "Respond with exactly: SMOKE_TEST_PASSED. Do not include any other text in your response.")

echo "Task created: ${TASK_ID}"

# --- Wait for agent to become healthy and produce a response ---
echo "--- Waiting for agent to connect and respond ---"
ELAPSED=0
AGENT_HEALTHY=false

while [[ ${ELAPSED} -lt ${TIMEOUT_SECONDS} ]]; do
  STATUS_OUTPUT=$(coder tasks status "${TASK_NAME}" --output json 2>/dev/null || echo "[]")

  if [[ "${STATUS_OUTPUT}" != "[]" ]]; then
    HEALTHY=$(echo "${STATUS_OUTPUT}" | jq -r '.healthy // .workspace_agent_health.healthy // empty' 2>/dev/null || true)
    STATE=$(echo "${STATUS_OUTPUT}" | jq -r '.state // .current_state // empty' 2>/dev/null || true)
    STATUS=$(echo "${STATUS_OUTPUT}" | jq -r '.status // empty' 2>/dev/null || true)

    echo "  [${ELAPSED}s] status=${STATUS} state=${STATE} healthy=${HEALTHY}"

    # Task failed
    if [[ "${STATUS}" == "failed" ]] || [[ "${STATE}" == "failed" ]]; then
      echo ""
      echo "FAIL: Task entered failed state"
      exit 1
    fi

    if [[ "${HEALTHY}" == "true" ]]; then
      AGENT_HEALTHY=true

      # Check task logs for the expected response
      LOGS_OUTPUT=$(coder tasks logs "${TASK_NAME}" --output json 2>/dev/null || echo "[]")
      RESPONSE=$(echo "${LOGS_OUTPUT}" | jq -r '.[] | select(.type == "output") | .content' 2>/dev/null | tr '\n' ' ')

      if echo "${RESPONSE}" | grep -q "SMOKE_TEST_PASSED"; then
        echo ""
        echo "--- Agent responded ---"
        echo "=== SMOKE TEST PASSED ==="
        echo "  Task created, agent connected, responded correctly."
        exit 0
      fi
    fi
  else
    echo "  [${ELAPSED}s] waiting for task to initialize..."
  fi

  sleep "${POLL_INTERVAL}"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

echo ""
if [[ "${AGENT_HEALTHY}" != "true" ]]; then
  echo "FAIL: Agent did not become healthy within ${TIMEOUT_SECONDS}s"
else
  echo "FAIL: Agent healthy but did not respond with SMOKE_TEST_PASSED within ${TIMEOUT_SECONDS}s"
fi
exit 1
