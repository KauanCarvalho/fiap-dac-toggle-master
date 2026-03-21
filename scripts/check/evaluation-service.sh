#!/usr/bin/env bash

set -euo pipefail

# Setup directories and load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

check_dependencies

# Use environment variable or default for port/base URL
DEFAULT_PORT="${PORT_EVALUATION_SERVICE:-8004}"
DEFAULT_BASE_URL="http://localhost:${DEFAULT_PORT}"
BASE_URL="${1:-$DEFAULT_BASE_URL}"

FLAG_NAME="eval-check-flag-$(random_string)"
USER_ID="user-$(random_string)"

echo "Using base URL: $BASE_URL"
echo "---------------------------------------------"

# 1. Health check
echo "Checking health endpoint..."

resp=$(call GET "$BASE_URL/health")
status=$(response_status "$resp")
body=$(response_body "$resp")

print_response "$status" "$body"

if [[ "$status" -ne 200 ]]; then
  echo "Health check failed"
  exit 1
fi

# 2. Setup Dependencies
echo "Setting up flag and rule for evaluation check..."

FLAG_BASE_URL="${FLAG_SERVICE_EXTERNAL_URL:-http://localhost:${PORT_FLAG_SERVICE:-8002}}"
TARGETING_BASE_URL="${TARGETING_SERVICE_EXTERNAL_URL:-http://localhost:${PORT_TARGETING_SERVICE:-8003}}"

# Use pre-seeded Service API Key for evaluation-service to call others
SERVICE_API_KEY="${EVALUATION_SERVICE_API_KEY:-tm_key_local_evaluation_service_fixed_key_123}"
AUTH_HEADER="Authorization: Bearer $SERVICE_API_KEY"

echo "Creating flag '$FLAG_NAME' via flag-service..."
resp=$(call POST "$FLAG_BASE_URL/flags" \
  "{\"name\":\"$FLAG_NAME\",\"is_enabled\":true,\"description\":\"Evaluation check\"}" \
  "$AUTH_HEADER")
print_response "$(response_status "$resp")" "$(response_body "$resp")"

if [[ "$(response_status "$resp")" -ne 201 ]]; then
  echo "Flag creation failed! Ensure EVALUATION_SERVICE_API_KEY is correct."
  exit 1
fi

echo "Creating 100% percentage rule for flag '$FLAG_NAME' via targeting-service..."
resp=$(call POST "$TARGETING_BASE_URL/rules" \
  "{\"flag_name\":\"$FLAG_NAME\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":100}}" \
  "$AUTH_HEADER")
print_response "$(response_status "$resp")" "$(response_body "$resp")"

if [[ "$(response_status "$resp")" -ne 201 ]]; then
  echo "Rule creation failed!"
  exit 1
fi

echo "---------------------------------------------"

# 3. Perform Evaluation
echo "Checking evaluation for user '$USER_ID' on flag '$FLAG_NAME'..."

resp=$(call GET "$BASE_URL/evaluate?user_id=$USER_ID&flag_name=$FLAG_NAME")
status=$(response_status "$resp")
body=$(response_body "$resp")

print_response "$status" "$body"

if [[ "$status" -ne 200 ]]; then
  echo "Evaluation failed with status: $status"
  exit 1
fi

result=$(echo "$body" | jq -r '.result')
if [[ "$result" == "true" ]]; then
  echo "Result: ENABLED (Success)"
else
  echo "Result: DISABLED (Unexpected for 100% rule)"
  exit 1
fi

echo "Evaluation service checks completed successfully"
