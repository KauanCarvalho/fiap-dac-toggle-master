#!/usr/bin/env bash

set -euo pipefail

# Setup directories and load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

check_dependencies

# Use environment variable or default for port/base URL
DEFAULT_PORT="${PORT_TARGETING_SERVICE:-8003}"
DEFAULT_BASE_URL="http://localhost:${DEFAULT_PORT}"
BASE_URL="${1:-$DEFAULT_BASE_URL}"

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

# 2. Authentication Setup
AUTH_HEADER=""
if [[ -n "${TARGETING_SERVICE_API_KEY:-}" ]]; then
  AUTH_HEADER="Authorization: Bearer $TARGETING_SERVICE_API_KEY"
else
  echo "TARGETING_SERVICE_API_KEY not set - creating a temporary key via auth-service..."
  AUTH_SERVICE_URL="http://localhost:${PORT_AUTH_SERVICE:-8001}"
  MASTER_KEY="${MASTER_KEY_AUTH_SERVICE:-super-secret-key}"
  
  key_resp=$(call POST "$AUTH_SERVICE_URL/admin/keys" \
    '{"name":"temp-targeting-check-key"}' \
    "Authorization: Bearer $MASTER_KEY")
  
  TEMP_KEY=$(echo "$(response_body "$key_resp")" | jq -r '.key')
  AUTH_HEADER="Authorization: Bearer $TEMP_KEY"
  echo "Created temporary API key: $TEMP_KEY"
fi

echo "---------------------------------------------"

# 3. Test Authorization
echo "Checking auth enforcement (no key)..."

resp=$(call GET "$BASE_URL/rules/some-flag")
status=$(response_status "$resp")

if [[ "$status" -ne 401 ]]; then
  echo "Auth enforcement failed (expected 401, got $status)"
  exit 1
else
  echo "Status: 401 (OK)"
fi

echo "---------------------------------------------"

# 4. CRUD Operations
FLAG_NAME="check-script-flag-$(random_string)"

echo "Creating rule for flag '$FLAG_NAME'..."
resp=$(call POST "$BASE_URL/rules" \
  "{\"flag_name\":\"$FLAG_NAME\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":50}}" \
  "$AUTH_HEADER")
print_response "$(response_status "$resp")" "$(response_body "$resp")"

if [[ "$(response_status "$resp")" -ne 201 ]]; then
  echo "Rule creation failed"
  exit 1
fi

echo "Getting rule for flag '$FLAG_NAME'..."
resp=$(call GET "$BASE_URL/rules/$FLAG_NAME" "" "$AUTH_HEADER")
print_response "$(response_status "$resp")" "$(response_body "$resp")"

echo "Updating rule for flag '$FLAG_NAME' (75%)..."
resp=$(call PUT "$BASE_URL/rules/$FLAG_NAME" \
  '{"is_enabled":true,"rules":{"type":"PERCENTAGE","value":75}}' \
  "$AUTH_HEADER")
print_response "$(response_status "$resp")" "$(response_body "$resp")"

echo "Deleting rule for flag '$FLAG_NAME'..."
resp=$(call DELETE "$BASE_URL/rules/$FLAG_NAME" "" "$AUTH_HEADER")
print_response "$(response_status "$resp")" "$(response_body "$resp")"

echo "Confirming rule for flag '$FLAG_NAME' no longer exists..."
resp=$(call GET "$BASE_URL/rules/$FLAG_NAME" "" "$AUTH_HEADER")
print_response "$(response_status "$resp")" "$(response_body "$resp")"

if [[ "$(response_status "$resp")" -ne 404 ]]; then
  echo "Rule deletion verification failed"
  exit 1
fi

echo "Targeting service checks completed successfully"
