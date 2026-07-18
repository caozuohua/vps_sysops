#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "backup smoke test requires root" >&2
  exit 77
fi
for command_name in sqlite3 tar sha256sum stat; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "missing test dependency: ${command_name}" >&2
    exit 77
  }
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d /tmp/vps-sysops-backup-test.XXXXXX)
cleanup() {
  case "${TEST_ROOT}" in
    /tmp/vps-sysops-backup-test.*) rm -rf -- "${TEST_ROOT}" ;;
    *) echo "refusing to remove unexpected test path: ${TEST_ROOT}" >&2 ;;
  esac
}
trap cleanup EXIT

mkdir -p "${TEST_ROOT}/source"
printf 'backup smoke test\n' > "${TEST_ROOT}/source/hello.txt"
sqlite3 "${TEST_ROOT}/source/app.db" \
  'CREATE TABLE items(id INTEGER PRIMARY KEY, value TEXT); INSERT INTO items(value) VALUES ("ok");'

PROFILE_FILE="${TEST_ROOT}/profile.conf"
cat > "${PROFILE_FILE}" <<EOF
BACKUP_SOURCES="${TEST_ROOT}/source"
BACKUP_DEST="${TEST_ROOT}/backups"
BACKUP_RETAIN_DAYS=7
SQLITE_DATABASES="${TEST_ROOT}/source/app.db"
CONFIGURE_LOGROTATE=false
EOF

VPS_PROFILE_FILE="${PROFILE_FILE}" bash "${ROOT_DIR}/scripts/04_backup.sh"

ARCHIVE=$(find "${TEST_ROOT}/backups" -maxdepth 1 -type f -name 'backup_*.tar.gz' -print -quit)
[[ -n "${ARCHIVE}" && -f "${ARCHIVE}.sha256" ]]
[[ "$(stat -c '%a' "${ARCHIVE}")" == "600" ]]
[[ "$(stat -c '%a' "${ARCHIVE}.sha256")" == "600" ]]
sha256sum -c "${ARCHIVE}.sha256"
tar -tzf "${ARCHIVE}" | grep -q '^sqlite/.\+\.sqlite3$'

mkdir -p "${TEST_ROOT}/restore"
tar -xzf "${ARCHIVE}" -C "${TEST_ROOT}/restore"
SNAPSHOT=$(find "${TEST_ROOT}/restore/sqlite" -type f -name '*.sqlite3' -print -quit)
[[ "$(sqlite3 "${SNAPSHOT}" 'PRAGMA integrity_check;')" == "ok" ]]
[[ "$(sqlite3 "${SNAPSHOT}" 'SELECT count(*) FROM items;')" == "1" ]]

echo "backup smoke test passed"
