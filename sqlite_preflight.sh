#!/usr/bin/env bash
set -euo pipefail

# ------ 0. Preconditions -------------------------------------------------
[[ $# -eq 1 ]] || { echo "Usage: $0 <database_file>"; exit 2; }
command -v sqlite3 >/dev/null || { echo "sqlite3 not installed"; exit 2; }

DB=$1
STAMP=$(date +%F_%H%M)
SAFE="${DB%.db}_readonly_${STAMP}.db"
LOG="preflight_${STAMP}.log"
INV="inventory_${STAMP}.txt" # User's suggestion for inventory file variable

# ------ 1. Copy & lock ---------------------------------------------------
cp --preserve=timestamps -- "$DB" "$SAFE"
chmod 0444 -- "$SAFE"

# ------ 2. Integrity + FK check -----------------------------------------
# Corrected heredoc placement and error message
if ! sqlite3 -readonly "$SAFE" >"$LOG" 2>&1 <<'SQL'
PRAGMA foreign_keys = ON;
PRAGMA integrity_check;
SQL
then
    echo "sqlite3 threw an error during integrity/FK check; see $LOG" # Adjusted error message
    exit 1
fi

# Verify the single-line output is exactly "ok"
# User's improved grep
if ! grep -Fxq "ok" "$LOG"; then
    echo "Integrity check failed; see $LOG"
    exit 1
fi

# ------ 3. Feature inventory --------------------------------------------
# Corrected heredoc placement and error message
if ! sqlite3 -readonly "$SAFE" >"$INV" 2>&1 <<'SQL'
.headers on
.mode column

-- Generated columns
SELECT tbl_name AS table_name
FROM sqlite_master
WHERE type='table' AND sql LIKE '%GENERATED ALWAYS%';

-- FTS5 virtual tables
SELECT name AS fts5_table
FROM sqlite_master
WHERE type='table'
  AND sql LIKE 'CREATE VIRTUAL TABLE%' AND sql LIKE '%fts5%';

-- Views (Re-integrated from our previous work)
SELECT name AS view_name
FROM sqlite_master
WHERE type='view';

-- INTEGER PRIMARY KEY aliases
SELECT tbl_name AS table_name
FROM sqlite_master
WHERE sql LIKE '%INTEGER PRIMARY KEY%';

-- REAL epoch columns
SELECT m.name AS "table_name", p.name AS "column_name"
FROM sqlite_master m
JOIN pragma_table_info(m.name) p
WHERE p.type='REAL'
  AND (p.name LIKE '%_time' OR p.name LIKE '%_timestamp');

-- JSON blobs
SELECT m.name AS "table_name", p.name AS "column_name"
FROM sqlite_master m
JOIN pragma_table_info(m.name) p
WHERE p.name LIKE '%_json' OR p.name LIKE '%json%';
SQL
then
    echo "sqlite3 failed during inventory; see $INV" # Adjusted error message
    exit 1
fi

echo "✅  Safe copy: $SAFE  |  Report: $LOG  |  Inventory: $INV"
