#!/usr/bin/env bash

set -euo pipefail

# Setup directories and load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

echo "================================================================"
echo "   ToggleMaster - Global Ecosystem Validation"
echo "================================================================"

# List of services to validate in logical order
SERVICES=(
  "auth-service"
  "flag-service"
  "targeting-service"
  "evaluation-service"
  "analytics-service"
)

TOTAL_SERVICES=${#SERVICES[@]}
SUCCESS_COUNT=0

# Iterate through services and run individual check scripts
for i in "${!SERVICES[@]}"; do
  SVC="${SERVICES[$i]}"
  echo ""
  echo "[$((i+1))/$TOTAL_SERVICES] Checking: $SVC..."
  echo "----------------------------------------------------------------"
  
  # Forward environment variables for cloud URLs if provided
  # Example: AUTH_SERVICE_URL, FLAG_SERVICE_URL, etc.
  if "$SCRIPT_DIR/$SVC.sh"; then
    echo "SUCCESS: $SVC is operational"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "FAILURE: $SVC check failed"
    echo ""
    echo "Verification interrupted due to failure in $SVC."
    exit 1
  fi
done

echo ""
echo "================================================================"
echo "   All $SUCCESS_COUNT services are operational"
echo "================================================================"
