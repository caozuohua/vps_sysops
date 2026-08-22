#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "new-api backup smoke test requires root" >&2
  exit 77
fi
for command_name in sqlite3 tar sha256sum; do
  command -v "${command_name}" >/dev/null 2>&1 || exit 77
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d /tmp/new-api-backup-test.XXXXXX)
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
mkdir -p "${TEST_ROOT}/new-api/data" "${TEST_ROOT}/backups"
printf 'API_KEY=test-only\n' >"${TEST_ROOT}/new-api/.env"
sqlite3 "${TEST_ROOT}/new-api/data/one-api.db" \
  'CREATE TABLE items(id INTEGER PRIMARY KEY, value TEXT); INSERT INTO items(value) VALUES ("ok");'

NEW_API_HOME="${TEST_ROOT}/new-api" \
NEW_API_BACKUP_DEST="${TEST_ROOT}/backups" \
NEW_API_BACKUP_MIN_FREE_MB=1 \
  bash "${ROOT_DIR}/scripts/new_api_backup.sh"

ARCHIVE=$(find "${TEST_ROOT}/backups" -maxdepth 1 -name 'new-api_*.tar.gz' -print -quit)
[[ -n "${ARCHIVE}" ]]
[[ "$(stat -c '%a' "${ARCHIVE}")" == "600" ]]
[[ "$(stat -c '%a' "${ARCHIVE}.sha256")" == "600" ]]
NEW_API_BACKUP_DEST="${TEST_ROOT}/backups" \
  bash "${ROOT_DIR}/scripts/new_api_backup.sh" verify "${ARCHIVE}"

echo "new-api backup smoke test passed"
