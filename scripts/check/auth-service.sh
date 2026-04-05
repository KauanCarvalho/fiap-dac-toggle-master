#!/usr/bin/env bash

set -euo pipefail

# Setup directories and load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

check_dependencies

# Use environment variable or default for port/base URL
DEFAULT_PORT="${PORT_AUTH_SERVICE:-8001}"
DEFAULT_BASE_URL="http://localhost:${DEFAULT_PORT}"
BASE_URL="${1:-$DEFAULT_BASE_URL}"

# Clean up MASTER_KEY_AUTH_SERVICE from any invisible characters/newlines
MASTER_KEY_AUTH_SERVICE=$(echo "${MASTER_KEY_AUTH_SERVICE:-super-secret-key}" | tr -d '\r\n ' )

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

# 2. Key Management check
echo "Creating API key... (Using MASTER_KEY: ${MASTER_KEY_AUTH_SERVICE:-NOT_SET})"

key_name="check-script-key"
resp=$(call POST "$BASE_URL/admin/keys" \
  "{\"name\":\"$key_name\"}" \
  "Authorization: Bearer ${MASTER_KEY_AUTH_SERVICE:-super-secret-key}")

status=$(response_status "$resp")
body=$(response_body "$resp")

print_response "$status" "$body"

if [[ "$status" -ne 201 ]]; then
  echo "Key creation failed"
  exit 1
fi

API_KEY=$(echo "$body" | jq -r '.key')
echo "Extracted API Key: $API_KEY"
echo "---------------------------------------------"

# 3. Validation check
echo "Validating created API key..."

resp=$(call GET "$BASE_URL/validate" "" "Authorization: Bearer $API_KEY")
status=$(response_status "$resp")
body=$(response_body "$resp")

print_response "$status" "$body"

if [[ "$status" -ne 200 ]]; then
  echo "API key validation failed"
  exit 1
fi

# 4. Invalid Key check
echo "Validating invalid API key..."

resp=$(call GET "$BASE_URL/validate" "" "Authorization: Bearer invalid_key")
status=$(response_status "$resp")
body=$(response_body "$resp")

print_response "$status" "$body"

if [[ "$status" -ne 401 ]]; then
  echo "Auth enforcement check failed (expected 401)"
  exit 1
fi

echo "Auth service checks completed successfully"
