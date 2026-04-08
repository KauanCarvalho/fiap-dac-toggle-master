#!/usr/bin/env bash

set -euo pipefail

# Setup directories and load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

check_dependencies

# Use environment variable or default for port/base URL
DEFAULT_PORT="${PORT_ANALYTICS_SERVICE:-8005}"
DEFAULT_BASE_URL="http://localhost:${DEFAULT_PORT}"
BASE_URL="${1:-$DEFAULT_BASE_URL}"

# Clean up variables from any invisible characters/newlines
MASTER_KEY_AUTH_SERVICE=$(echo "${MASTER_KEY_AUTH_SERVICE:-auth_master_key}" | tr -d '\r\n ' )

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

# 2. Verify Data (LocalStack or Cloud)
echo "Verifying processed events in DynamoDB..."

# Wait for background worker to process messages from SQS
echo "Waiting 5 seconds for background worker to process messages..."
sleep 5

# Cloud Readiness: Detect if we should use real AWS or LocalStack
if [[ -n "${AWS_SESSION_TOKEN:-}" ]] || [[ "${AWS_ENDPOINT_URL:-}" != *"localstack"* && -n "${AWS_ENDPOINT_URL:-}" ]]; then
  echo "Checking remote DynamoDB..."
  aws dynamodb scan --table-name analytics-events --max-items 5 --region "${AWS_REGION:-us-east-1}"
else
  echo "Checking LocalStack DynamoDB..."
  docker exec localstack awslocal dynamodb scan \
    --table-name analytics-events \
    --max-items 5
fi

echo "---------------------------------------------"
echo "Analytics service checks completed successfully"
