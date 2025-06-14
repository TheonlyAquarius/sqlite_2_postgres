#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# sqlite2pg_combined.sh - Unified SQLite → PostgreSQL migration script
# Usage: ./sqlite2pg_combined.sh /absolute/path/to/chat.db
# ---------------------------------------------------------------------------

[[ $# -eq 1 ]] || { echo "Usage: $0 <sqlite_db_path>"; exit 2; }
SQLITE_DB=$1

command -v sqlite3 >/dev/null || { echo "sqlite3 not found"; exit 2; }
command -v psql    >/dev/null || { echo "psql not found";  exit 2; }

# --- gather Postgres credentials ------------------------------------------
read -rp "Postgres host: " PGHOST
read -rp "Postgres port [5432]: " PGPORT
PGPORT=${PGPORT:-5432}
read -rp "Postgres user: " PGUSER
read -rp "Target database: " PGDATABASE
read -srp "Password for $PGUSER: " PGPASSWORD && echo
export PGPASSWORD PGHOST PGPORT PGUSER PGDATABASE

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

printf '\n📦  Migrating %s  →  %s@%s:%s/%s\n' "$SQLITE_DB" "$PGUSER" "$PGHOST" "$PGPORT" "$PGDATABASE"

# ---------------------------------------------------------------------------
# 1. Dump SQLite schema
# ---------------------------------------------------------------------------
echo "🔹 Dumping SQLite schema ..."
sqlite3 "$SQLITE_DB" .schema >"$WORKDIR/schema.sqlite.sql"

# ---------------------------------------------------------------------------
# 2. Rewrite schema for PostgreSQL
# ---------------------------------------------------------------------------
echo "🔹 Rewriting DDL for PostgreSQL ..."
SCHEMA_PG="$WORKDIR/schema.pg.sql"

sed -E "
  s/INTEGER PRIMARY KEY AUTOINCREMENT/SERIAL PRIMARY KEY/Ig;
  s/INTEGER PRIMARY KEY/SERIAL PRIMARY KEY/Ig;
  s/([[:space:]]+)([A-Za-z0-9_]*_(time|timestamp))[[:space:]]+REAL/\1\2 TIMESTAMPTZ/Ig;
  s/([[:space:]]+[^,]*_json)[[:space:]]+TEXT/\1 JSONB/Ig;
  s/(GENERATED ALWAYS AS [^)]*\))/\1 STORED/I;
  /CREATE VIRTUAL TABLE .* USING fts5/d;
  /PRAGMA/d;
" "$WORKDIR/schema.sqlite.sql" >"$SCHEMA_PG"

# ---------------------------------------------------------------------------
# 3. Apply schema in PostgreSQL
# ---------------------------------------------------------------------------
echo "🔹 Applying transformed schema in PostgreSQL ..."
psql -v ON_ERROR_STOP=1 -q -f "$SCHEMA_PG"

# ---------------------------------------------------------------------------
# 4. Export SQLite tables and import via COPY
# ---------------------------------------------------------------------------
echo "🔹 Migrating table data ..."
sqlite3 "$SQLITE_DB" ".schema" | grep 'CREATE TABLE' | sed 's/CREATE TABLE \(IF NOT EXISTS \)\?"\?\([^" ]\+\)"\?.*/\2/' > "$WORKDIR/table_list"

while read -r TABLE; do
  [[ -z "$TABLE" || "$TABLE" =~ ^message_fts ]] && continue
  echo "     • $TABLE"
  CSV="$WORKDIR/$(printf '%q' "$TABLE").csv"
  sqlite3 -header -csv "$SQLITE_DB" "SELECT * FROM \"$TABLE\";" >"$CSV"
  psql -v ON_ERROR_STOP=1 -q -c \
    "\\copy \"$TABLE\" FROM PROGRAM 'cat \"$CSV\"' WITH (FORMAT CSV, HEADER TRUE, NULL '', ENCODING 'UTF8')" || {
      echo "⚠️  Failed to import $TABLE. Check CSV or JSON validity." >&2
      exit 1
    }
done <"$WORKDIR/table_list"

# ---------------------------------------------------------------------------
# 5. Re-create FTS functionality using tsvector
# ---------------------------------------------------------------------------
echo "🔹 Building full-text search column & trigger ..."
psql -v ON_ERROR_STOP=1 -q <<'PSQL'
ALTER TABLE messages ADD COLUMN IF NOT EXISTS text_search tsvector;
UPDATE messages
   SET text_search = to_tsvector('english', coalesce(text_content,''));

CREATE INDEX IF NOT EXISTS messages_text_search_idx
        ON messages USING GIN (text_search);

CREATE OR REPLACE FUNCTION messages_tsv_trigger() RETURNS trigger AS $$
BEGIN
  NEW.text_search := to_tsvector('english', coalesce(NEW.text_content,''));
  RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS messages_tsv_update ON messages;
CREATE TRIGGER messages_tsv_update
BEFORE INSERT OR UPDATE ON messages
FOR EACH ROW EXECUTE FUNCTION messages_tsv_trigger();
PSQL

# ---------------------------------------------------------------------------
# 6. Re-create conversation_stats view
# ---------------------------------------------------------------------------
echo "🔹 Re-creating conversation_stats view ..."
psql -v ON_ERROR_STOP=1 -q <<'PSQL'
CREATE OR REPLACE VIEW conversation_stats AS
SELECT c.conversation_id,
       c.title,
       c.created_date,
       COUNT(m.message_id) AS total_messages,
       SUM(CASE WHEN r.role_name = 'user'      THEN 1 ELSE 0 END) AS user_messages,
       SUM(CASE WHEN r.role_name = 'assistant' THEN 1 ELSE 0 END) AS assistant_messages,
       SUM(CASE WHEN r.role_name = 'system'    THEN 1 ELSE 0 END) AS system_messages,
       SUM(CASE WHEN r.role_name = 'tool'      THEN 1 ELSE 0 END) AS tool_messages,
       SUM(m.word_count) AS total_words,
       COUNT(DISTINCT a.attachment_id) AS attachments,
       COUNT(DISTINCT ci.citation_id) AS citations
FROM   conversations c
LEFT JOIN messages    m  ON m.conversation_id = c.conversation_id
LEFT JOIN roles       r  ON r.role_id        = m.role_id
LEFT JOIN attachments a  ON a.message_id     = m.message_id
LEFT JOIN citations   ci ON ci.message_id    = m.message_id
GROUP BY c.conversation_id, c.title, c.created_date;
PSQL

echo "✅  Migration complete."
