#!/usr/bin/env bash

set -euo pipefail

base_url="${TASKFLOW_BASE_URL:-http://127.0.0.1:8080}"
host_header="${TASKFLOW_HOST_HEADER:-taskflow.local}"
evidence_dir="${EVIDENCE_DIR:-./delivery-evidence}"
mkdir -p "$evidence_dir"

curl_args=(
  --fail
  --silent
  --show-error
  --connect-timeout 3
  --max-time 15
)

if [[ -n "$host_header" ]]; then
  curl_args+=(--header "Host: $host_header")
fi

wait_for_endpoint() {
  local path="$1"
  local output_file="$2"

  for _attempt in {1..60}; do
    if curl "${curl_args[@]}" "$base_url$path" --output "$output_file"; then
      return 0
    fi
    sleep 2
  done

  echo "Endpoint did not become available: $path" >&2
  return 1
}

wait_for_endpoint "/health/live" "$evidence_dir/health-live.json"
wait_for_endpoint "/health/ready" "$evidence_dir/health-ready.json"

curl "${curl_args[@]}" \
  "$base_url/docs" \
  --output "$evidence_dir/docs.html"

task_title="CD smoke test $(date -u +%Y%m%dT%H%M%SZ)"
task_payload="$(printf '{"title":"%s","description":"Ephemeral delivery validation","priority":"high"}' "$task_title")"

curl "${curl_args[@]}" \
  --request POST \
  --header "Content-Type: application/json" \
  --data "$task_payload" \
  "$base_url/api/v1/tasks" \
  --output "$evidence_dir/task-created.json"

task_id="$(python3 - "$evidence_dir/task-created.json" "$task_title" <<'PY'
import json
import sys

path, expected_title = sys.argv[1:]
with open(path, encoding="utf-8") as response_file:
    task = json.load(response_file)

if task.get("title") != expected_title:
    raise SystemExit("Created task title does not match the request")
if not task.get("id"):
    raise SystemExit("Created task does not contain an id")

print(task["id"])
PY
)"

curl "${curl_args[@]}" \
  "$base_url/api/v1/tasks/$task_id" \
  --output "$evidence_dir/task-fetched.json"

curl "${curl_args[@]}" \
  "$base_url/api/v1/tasks" \
  --output "$evidence_dir/tasks-list.json"

python3 - \
  "$evidence_dir/task-fetched.json" \
  "$evidence_dir/tasks-list.json" \
  "$task_id" <<'PY'
import json
import sys

fetched_path, list_path, expected_id = sys.argv[1:]

with open(fetched_path, encoding="utf-8") as response_file:
    fetched = json.load(response_file)
with open(list_path, encoding="utf-8") as response_file:
    tasks = json.load(response_file)

if fetched.get("id") != expected_id:
    raise SystemExit("Fetched task does not match the created task")
if not any(task.get("id") == expected_id for task in tasks):
    raise SystemExit("Created task is absent from the task collection")
PY

{
  echo "TaskFlow smoke test: PASS"
  echo "Base URL: $base_url"
  echo "Host header: ${host_header:-not used}"
  echo "Validated endpoints:"
  echo "- /health/live"
  echo "- /health/ready"
  echo "- /docs"
  echo "- POST /api/v1/tasks"
  echo "- GET /api/v1/tasks/{id}"
  echo "- GET /api/v1/tasks"
  echo "Created task id: $task_id"
} | tee "$evidence_dir/smoke-summary.txt"
