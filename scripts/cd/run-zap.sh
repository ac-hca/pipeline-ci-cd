#!/usr/bin/env bash

set -euo pipefail

zap_image="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:2.17.0}"
zap_target="${ZAP_TARGET:-http://127.0.0.1:8000/openapi.json}"
zap_network_mode="${ZAP_NETWORK_MODE:-host}"
evidence_dir="${EVIDENCE_DIR:-./delivery-evidence}"
rules_file="${ZAP_RULES_FILE:-security/zap/rules.tsv}"

if [[ ! -f "$rules_file" ]]; then
  echo "ZAP rules file does not exist: $rules_file" >&2
  exit 1
fi

mkdir -p "$evidence_dir/zap"
evidence_dir="$(cd "$evidence_dir" && pwd)"
cp "$rules_file" "$evidence_dir/zap/rules.tsv"

# The official image runs as UID 1000 and must write reports into this ephemeral directory.
chmod 0777 "$evidence_dir/zap"

docker pull "$zap_image"
docker image inspect \
  --format '{{join .RepoDigests "\n"}}' \
  "$zap_image" >"$evidence_dir/zap/image-digests.txt"

case "$zap_network_mode" in
  host)
    docker_network_args=(--network host)
    ;;
  bridge)
    docker_network_args=(--add-host host.docker.internal:host-gateway)
    ;;
  *)
    echo "ZAP_NETWORK_MODE must be host or bridge" >&2
    exit 1
    ;;
esac

set +e
docker run --rm \
  "${docker_network_args[@]}" \
  --volume "$evidence_dir/zap:/zap/wrk:rw" \
  "$zap_image" \
  zap-api-scan.py \
  -t "$zap_target" \
  -f openapi \
  -c /zap/wrk/rules.tsv \
  -i \
  -I \
  -s \
  -l INFO \
  -T 5 \
  -z "-config autoupdate.checkOnStart=false -config autoupdate.downloadNewRelease=false -config autoupdate.installAddonUpdates=false -config autoupdate.installScannerRules=false" \
  -r zap-report.html \
  -J zap-report.json \
  -w zap-report.md 2>&1 | tee "$evidence_dir/zap/console.log"
zap_status="${PIPESTATUS[0]}"

host_uid="$(id -u)"
host_gid="$(id -g)"
docker run --rm \
  --user 0:0 \
  --volume "$evidence_dir/zap:/zap/wrk:rw" \
  "$zap_image" \
  chown -R "${host_uid}:${host_gid}" /zap/wrk
permission_status="$?"
set -e

if [[ "$permission_status" -ne 0 ]]; then
  echo "Could not normalize OWASP ZAP report ownership" >&2
  exit "$permission_status"
fi

chmod -R u+rwX,go+rX "$evidence_dir/zap"

if [[ "$zap_status" -ne 0 ]]; then
  echo "OWASP ZAP failed with exit code $zap_status" >&2
  exit "$zap_status"
fi

echo "OWASP ZAP API scan: PASS" | tee "$evidence_dir/zap/summary.txt"
