#!/usr/bin/env bash
# Sauvegarde automatique journalière de la base Loyatrack.
# - PostgreSQL : utilise pg_dump (si DATABASE_URL / variables PG définies)
# - Sinon : repli sur `manage.py backup_data` (dumpdata JSON, portable SQLite)
#
# Planification cron (tous les jours à 3h) :
#   0 3 * * * /chemin/vers/backend/scripts/backup.sh >> /var/log/loyatrack-backup.log 2>&1
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="${LOYATRACK_BACKUP_DIR:-$BACKEND_DIR/backups}"
STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -n "${PGDATABASE:-}" ]; then
  echo "[backup] pg_dump de $PGDATABASE"
  pg_dump --no-owner --format=custom "$PGDATABASE" > "$BACKUP_DIR/loyatrack_$STAMP.dump"
else
  echo "[backup] dumpdata (repli)"
  "$BACKEND_DIR/env/Scripts/python.exe" "$BACKEND_DIR/Loyatrack/manage.py" backup_data --dossier "$BACKUP_DIR"
fi

# Rotation : conserver les 30 dernières sauvegardes
ls -1t "$BACKUP_DIR"/* 2>/dev/null | tail -n +31 | xargs -r rm -f
echo "[backup] terminé : $BACKUP_DIR"
