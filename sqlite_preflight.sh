# --- sqlite_preflight.sh -------------------------------------------------
#!/usr/bin/env bash
set -euo pipefail

# Check for command-line argument
if [ "$#" -ne 1 ]; then
    echo "Usage: ./sqlite_preflight.sh <database_file_path>"
    exit 1
fi

# Check for sqlite3 command
if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 command not found. Please install sqlite3."
    exit 1
fi

DB="$1"                                   # chat.db (original)
STAMP=$(date +%F_%H%M)
SAFE="${DB%.db}_readonly_$STAMP.db"        # chat_readonly_2025-06-13_1810.db
LOG="preflight_${STAMP}.log"              # full diagnostic log

# 1. Copy & lock down ----------------------------------------------------------------
cp --preserve=timestamps "$DB" "$SAFE" || { echo "Error: Failed to copy the database file."; exit 1; }
chmod 0444 "$SAFE" || { echo "Error: Failed to set permissions for the database file."; exit 1; }

# 2. Integrity & FK enforcement -------------------------------------------------------
if ! sqlite3 -readonly "$SAFE" <<'SQL' >"$LOG" 2>&1; then
PRAGMA foreign_keys = ON;      -- enforce constraints for this session :contentReference[oaicite:2]{index=2}
PRAGMA integrity_check;        -- deep corruption scan (prints “ok” if clean) :contentReference[oaicite:3]{index=3}
SQL
    echo "Error: sqlite3 command failed during integrity check. Check $LOG for details."
    exit 1
fi

# Check if integrity check passed (sqlite3 prints "ok" on success)
if ! grep -q "ok" "$LOG"; then
    echo "Error: Database integrity check failed. Check $LOG for details."
    exit 1
fi

# 3. Feature inventory into separate file -------------------------------------------
if ! sqlite3 -readonly "$SAFE" <<'SQL' > "inventory_${STAMP}.txt" 2>&1; then
.headers on
.mode column
-- Generated / hidden columns
SELECT tbl_name AS table_name
FROM sqlite_master
WHERE type='table'
  AND sql LIKE '%GENERATED ALWAYS%';               -- detects stored generated cols :contentReference[oaicite:4]{index=4}

-- FTS5 virtual tables
SELECT name AS fts5_table
FROM sqlite_master
WHERE type='table'
  AND sql LIKE 'CREATE VIRTUAL TABLE%'
  AND sql LIKE '%fts5%';                           -- FTS5 virtual tables :contentReference[oaicite:5]{index=5}

-- INTEGER PRIMARY KEY aliases (rowid)
SELECT tbl_name AS table_name
FROM sqlite_master
WHERE sql LIKE '%INTEGER PRIMARY KEY%';           -- rowid alias inspection :contentReference[oaicite:6]{index=6}

-- REAL columns that look like Unix-epoch timestamps
SELECT m.name AS table_name, p.name AS column_name
FROM sqlite_master m
JOIN pragma_table_info(m.name) p
WHERE p.type='REAL'
  AND (p.name LIKE '%_time' OR p.name LIKE '%_timestamp');

-- Likely JSON blobs
SELECT m.name, p.name
FROM sqlite_master m
JOIN pragma_table_info(m.name) p
WHERE p.name LIKE '%_json' OR p.name LIKE '%json%'; -- spot JSON1 targets :contentReference[oaicite:7]{index=7}
SQL
    echo "Error: sqlite3 command failed during feature inventory. Check inventory_${STAMP}.txt for details."
    exit 1
fi

echo "✅ Pre-flight done.  Safe copy: $SAFE  |  Report: $LOG  |  Inventory: inventory_${STAMP}.txt"
# ------------------------------------------------------------------------
