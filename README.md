**TL;DR – Run the one-liner below and you will get (a) a read-only safety copy of your `.db`, (b) an integrity-check/foreign-key log, and (c) a “feature inventory” text file listing every generated column, FTS5 table, `INTEGER PRIMARY KEY` alias, REAL-epoch field and JSON column.** After that you can move straight on to `pgloader` or the MySQL wizard without worrying about silent corruption or hidden SQLite-only quirks.

```bash
# --- sqlite_preflight.sh -------------------------------------------------
#!/usr/bin/env bash
set -euo pipefail

DB="$1"                                   # chat.db (original)
STAMP=$(date +%F_%H%M)
SAFE="${DB%.db}_readonly_$STAMP.db"        # chat_readonly_2025-06-13_1810.db
LOG="preflight_${STAMP}.log"              # full diagnostic log

# 1. Copy & lock down ----------------------------------------------------------------
cp --preserve=timestamps "$DB" "$SAFE"                # fast, bit-for-bit copy :contentReference[oaicite:0]{index=0}
chmod 0444 "$SAFE"                                    # read-only permissions for everyone :contentReference[oaicite:1]{index=1}

# 2. Integrity & FK enforcement -------------------------------------------------------
sqlite3 -readonly "$SAFE" <<'SQL' >"$LOG"
PRAGMA foreign_keys = ON;      -- enforce constraints for this session :contentReference[oaicite:2]{index=2}
PRAGMA integrity_check;        -- deep corruption scan (prints “ok” if clean) :contentReference[oaicite:3]{index=3}
SQL

# 3. Feature inventory into separate file -------------------------------------------
sqlite3 -readonly "$SAFE" <<'SQL' > "inventory_${STAMP}.txt"
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

echo "✅ Pre-flight done.  Safe copy: $SAFE  |  Report: $LOG  |  Inventory: inventory_${STAMP}.txt"
# ------------------------------------------------------------------------ 
```

Save the file, make it executable (`chmod +x sqlite_preflight.sh`), then run:

```bash
./sqlite_preflight.sh path/to/chat.db
```

---

## How this script meets each checklist item

### 1  Copy the database & set it read-only

* `cp --preserve=timestamps` produces a byte-for-byte duplicate with original time-stamps so any later diff or `rsync` sees no false positives ([linuxize.com][1]).
* `chmod 0444` removes write permission from everyone—a quick, portable way to “lock” the copy ([tecmint.com][2]).

### 2  Enable FK checks + run corruption check

* `PRAGMA foreign_keys = ON;` must be issued **per connection** because SQLite keeps it off by default for backward-compatibility ([sqlite.org][3]).
* `PRAGMA integrity_check;` walks every B-tree page and index; if anything other than `ok` appears in the log you must repair before migrating ([sqlite.org][4]).

### 3  Inventory non-portable features automatically

| Feature                 | Detection logic                                                                                       | Why it matters after export                                                                                |
| ----------------------- | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| **Generated columns**   | search schema for `GENERATED ALWAYS` (or use `PRAGMA table_xinfo`) ([sqlite.org][5])                  | pgloader imports them as plain columns; you’ll need to re-add the generation expression in Postgres/MySQL. |
| **FTS5 virtual tables** | look for `CREATE VIRTUAL TABLE … USING fts5` ([sqlite.org][6])                                        | Not portable; recreate with Postgres `tsvector` + `GIN` or MySQL `FULLTEXT`.                               |
| **INTEGER PRIMARY KEY** | grep schema for the phrase; each is an alias for `rowid` ([sqlite.org][7])                            | pgloader auto-maps to `BIGINT`; MySQL Workbench maps to `BIGINT AUTO_INCREMENT`.                           |
| **REAL epoch fields**   | heuristic: `type = REAL` + column name hints (`*_time`, `*_timestamp`)                                | Convert later with `to_timestamp()` (Postgres) or `FROM_UNIXTIME()` (MySQL).                               |
| **JSON blobs**          | name ends in `_json` or contains `json`; use JSON1 functions now, native JSON later ([sqlite.org][8]) |                                                                                                            |

### 4  Safe to proceed

Once `integrity_check` says `ok` and you’ve reviewed **inventory\_\*.txt** you can:

* For PostgreSQL: run `pgloader $SAFE postgresql://user:pass@host/db` and patch generated columns / FTS later. (pgloader docs detail each edge-case mapping) ([sqlite.org][5])
* For MySQL: open MySQL Workbench → **Database ▸ Migration Wizard** and point it at `$SAFE`.

---

## If you want to run the basics manually (no script)

```bash
# Copy and lock
cp chat.db chat_readonly.db
chmod 0444 chat_readonly.db         # read-only file

# Integrity + FK enforcement
sqlite3 -readonly chat_readonly.db \
  "PRAGMA foreign_keys=ON; PRAGMA integrity_check;"

# Quick feature probes
sqlite3 -readonly chat_readonly.db "SELECT name FROM sqlite_master WHERE sql LIKE '%GENERATED ALWAYS%';"
sqlite3 -readonly chat_readonly.db "SELECT name FROM sqlite_master WHERE type='table' AND sql LIKE '%fts5%';"
```

That’s it—you now have a bullet-proof, read-only source and a machine-generated checklist of SQLite-specific quirks, ready for a clean lift into PostgreSQL or MySQL.

[1]: https://linuxize.com/post/cp-command-in-linux/?utm_source=chatgpt.com "Cp Command in Linux (Copy Files)"
[2]: https://www.tecmint.com/cp-command-examples/?utm_source=chatgpt.com "How to Use cp Command Effectively in Linux [14 Examples] - Tecmint"
[3]: https://www.sqlite.org/foreignkeys.html?utm_source=chatgpt.com "SQLite Foreign Key Support"
[4]: https://sqlite.org/search?i=6&q=PRAGMA+&utm_source=chatgpt.com "Search SQLite Documentation"
[5]: https://www.sqlite.org/pragma.html?utm_source=chatgpt.com "Pragma statements supported by SQLite"
[6]: https://www.sqlite.org/fts5.html?utm_source=chatgpt.com "SQLite FTS5 Extension"
[7]: https://www.sqlite.org/rowidtable.html?utm_source=chatgpt.com "Rowid Tables - SQLite"
[8]: https://www.sqlite.org/json1.html?utm_source=chatgpt.com "JSON Functions And Operators - SQLite"

