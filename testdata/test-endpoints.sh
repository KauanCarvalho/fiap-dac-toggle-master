#!/usr/bin/env bash
set -euo pipefail

base_url="${1:-}"
shift || true

TIMEOUT=5

if [[ -z "$base_url" ]]; then
  echo "Usage: $0 <base_url>"
  exit 1
fi

check_dependencies() {
  local missing=()

  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v jq >/dev/null 2>&1 || missing+=("jq")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing dependencies: ${missing[*]}"
    echo "  sudo apt update && sudo apt install -y ${missing[*]}"

    exit 1
  fi
}

rand_str() {
  echo "feat_$(date +%s%N | sha256sum | head -c8)"
}

call() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"
  local resp

  resp=$(curl --silent --show-error --max-time "$TIMEOUT" --write-out "HTTPSTATUS:%{http_code}" --location -X "$method" "$url" ${data:+--header 'Content-Type: application/json' --data "$data"})

  local body status

  body=$(echo "$resp" | sed -e 's/HTTPSTATUS\:.*//g')
  status=$(echo "$resp" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  echo "${status}|${body}"
}

pretty_print() {
  local status="$1"
  local body="$2"

  echo "Status: $status"

  if [[ -z "$body" ]]; then
    echo "No Body"
  else
    if echo "$body" | jq . >/dev/null 2>&1; then
      echo "$body" | jq .
    else
      echo "$body"
    fi
  fi

  echo "---------------------------------------------"
}

check_dependencies

echo "Base URL: $base_url"
echo "---------------------------------------------"

# 1) GET /health -> expect 200.
echo "GET /health"

health_resp=$(call GET "${base_url%/}/health")
health_status=$(echo "$health_resp" | cut -d'|' -f1)
health_body=$(echo "$health_resp" | cut -d'|' -f2-)

pretty_print "$health_status" "$health_body"
if [[ "$health_status" -ne 200 ]]; then
  echo "Healthcheck failed, aborting."
  exit 1
fi

# 2) GET /flags/<nonexistent> -> expect 404.
rand_name="$(rand_str)"

echo "GET /flags/${rand_name}"

resp=$(call GET "${base_url%/}/flags/${rand_name}")
status=$(echo "$resp" | cut -d'|' -f1)
body=$(echo "$resp" | cut -d'|' -f2-)

pretty_print "$status" "$body"

# 3) GET /flags -> expect empty list (first call).
echo "GET /flags"

resp=$(call GET "${base_url%/}/flags")
status=$(echo "$resp" | cut -d'|' -f1)
body=$(echo "$resp" | cut -d'|' -f2-)

pretty_print "$status" "$body"

# 4) POST /flags -> create a new feature (feat1).
feat1="$(rand_str)"
payload="{\"name\":\"${feat1}\",\"is_enabled\":true}"

echo "POST /flags -> create ${feat1}"

resp=$(call POST "${base_url%/}/flags" "$payload")
status=$(echo "$resp" | cut -d'|' -f1)
body=$(echo "$resp" | cut -d'|' -f2-)

pretty_print "$status" "$body"

# 5) GET /flags/<feat1> -> expect to get the created feature.
echo "GET /flags/${feat1}"

resp=$(call GET "${base_url%/}/flags/${feat1}")
status=$(echo "$resp" | cut -d'|' -f1)
body=$(echo "$resp" | cut -d'|' -f2-)

pretty_print "$status" "$body"

# 6) POST /flags -> create another feature (feat2).
feat2="$(rand_str)"
payload2="{\"name\":\"${feat2}\",\"is_enabled\":true}"

echo "POST /flags -> create ${feat2}"

resp=$(call POST "${base_url%/}/flags" "$payload2")
status=$(echo "$resp" | cut -d'|' -f1)
body=$(echo "$resp" | cut -d'|' -f2-)

pretty_print "$status" "$body"

# 7) PUT /flags/<feat2> -> set is_enabled=false.
update_payload="{\"is_enabled\":false}"

echo "PUT /flags/${feat2} -> set is_enabled=false"

resp=$(call PUT "${base_url%/}/flags/${feat2}" "$update_payload")
status=$(echo "$resp" | cut -d'|' -f1)
body=$(echo "$resp" | cut -d'|' -f2-)

pretty_print "$status" "$body"

# 8) GET /flags -> expect to see both features with correct states.
echo "GET /flags (final list)"

resp=$(call GET "${base_url%/}/flags")
status=$(echo "$resp" | cut -d'|' -f1)
body=$(echo "$resp" | cut -d'|' -f2-)

pretty_print "$status" "$body"

echo "Done."
