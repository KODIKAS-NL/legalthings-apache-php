#!/usr/bin/env bash
# Runs in-container.sh in every running container (or the ones given as arguments) on this host.
# Usage: sudo ./host-runner.sh [container ...]
set -u
cd "$(dirname "$0")"

containers=("$@")
if [ ${#containers[@]} -eq 0 ]; then
  mapfile -t containers < <(docker ps --format '{{.Names}}')
fi

summary=()
for c in "${containers[@]}"; do
  case "$c" in *portainer*|*elasticsearch*|*mongo*) continue ;; esac
  echo "################ $c"
  if ! docker exec "$c" sh -c 'command -v bash' >/dev/null 2>&1; then
    summary+=("$(printf '%-40s %s' "$c" 'SKIPPED (no bash)')")
    continue
  fi
  out=$(docker exec -u root -i "$c" bash -s < in-container.sh 2>&1)
  echo "$out"
  result=$(echo "$out" | grep '^RESULT:' | tail -1)
  summary+=("$(printf '%-40s %s' "$c" "${result:-RESULT: FAIL no result line}")")
done

echo
echo "================ summary"
printf '%s\n' "${summary[@]}"
