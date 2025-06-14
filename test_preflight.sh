#!/usr/bin/env bash
set -euo pipefail

# Test script for sqlite_preflight.sh

DB_FILE="test_db.sqlite"
PREFLIGHT_SCRIPT="./sqlite_preflight.sh"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    rm -f "$DB_FILE"
    rm -f "${DB_FILE%.sqlite}_readonly_"*".db"
    rm -f "preflight_"*".log"
    rm -f "inventory_"*".txt"
}

# Trap EXIT signal to ensure cleanup happens
trap cleanup EXIT

# 1. Create a dummy SQLite database with various features
echo "Creating dummy database: $DB_FILE"
sqlite3 "$DB_FILE" <<SQL
CREATE TABLE simple_table (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO simple_table (id, name) VALUES (1, 'Test Data');

CREATE VIEW test_view AS SELECT id, name FROM simple_table WHERE id = 1;

CREATE VIRTUAL TABLE test_fts USING fts5(content, id UNINDEXED);
INSERT INTO test_fts (id, content) VALUES (1, 'This is some searchable text.');

CREATE TABLE generated_col_test (
    id INTEGER PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    full_name TEXT GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED
);
INSERT INTO generated_col_test (first_name, last_name) VALUES ('John', 'Doe');

CREATE TABLE another_table (
    entry_time REAL, -- for timestamp check, changed from entry_date
    data_json TEXT   -- for json check
);
INSERT INTO another_table (entry_time, data_json) VALUES (strftime('%s','now'), '{"key": "value"}');
SQL

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Failed to create dummy database $DB_FILE"
    exit 1
fi

# 2. Run the preflight script
echo "Running preflight script..."
if ! "$PREFLIGHT_SCRIPT" "$DB_FILE"; then
    echo "Error: sqlite_preflight.sh failed to execute."
    # Attempt to display logs if they exist, then exit
    if ls preflight_*.log 1> /dev/null 2>&1; then
        echo "--- Preflight Log ---"
        cat preflight_*.log
        echo "---------------------"
    fi
    if ls inventory_*.txt 1> /dev/null 2>&1; then
        echo "--- Inventory Log ---"
        cat inventory_*.txt
        echo "---------------------"
    fi
    exit 1
fi
echo "Preflight script executed successfully."

# 3. Verify inventory file creation and content
echo "Verifying inventory file..."
INVENTORY_FILE=$(ls inventory_*.txt | head -n 1) # Get the most recent inventory file

if [ ! -f "$INVENTORY_FILE" ]; then
    echo "Error: Inventory file not found!"
    exit 1
fi
echo "Inventory file found: $INVENTORY_FILE"

# Check for view
if ! grep -q "test_view" "$INVENTORY_FILE"; then
    echo "Error: View 'test_view' not found in inventory."
    cat "$INVENTORY_FILE"
    exit 1
fi
echo "View 'test_view' found."

# Check for FTS5 table
if ! grep -q "test_fts" "$INVENTORY_FILE"; then
    echo "Error: FTS5 table 'test_fts' not found in inventory."
    cat "$INVENTORY_FILE"
    exit 1
fi
echo "FTS5 table 'test_fts' found."

# Check for generated column table (by table name)
# The script detects tables with generated columns, not the columns themselves directly in a list
if ! grep -A 1 "generated_col_test" "$INVENTORY_FILE" | grep -q "generated_col_test"; then
    echo "Error: Table with generated column 'generated_col_test' not found in inventory section for generated columns."
    cat "$INVENTORY_FILE"
    exit 1
fi
echo "Table 'generated_col_test' (with generated column) found."

# Check for timestamp-like column (by table name, as column name might be too generic)
if ! grep -A 2 "another_table" "$INVENTORY_FILE" | grep -qw "entry_time"; then # Using -qw for whole word, and A 2 to be safe
    echo "Error: Table 'another_table' with timestamp-like column 'entry_time' not found in inventory."
    cat "$INVENTORY_FILE"
    exit 1
fi
echo "Table 'another_table' with 'entry_time' found."

# Check for JSON-like column (by table name)
if ! grep -A 1 "another_table" "$INVENTORY_FILE" | grep -q "data_json"; then
    echo "Error: Table 'another_table' with JSON-like column 'data_json' not found in inventory."
    cat "$INVENTORY_FILE"
    exit 1
fi
echo "Table 'another_table' with 'data_json' found."


# Check for integrity check "ok" in the main log
LOG_FILE=$(ls preflight_*.log | head -n 1)
if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file not found!"
    exit 1
fi
if ! grep -q "ok" "$LOG_FILE"; then
    echo "Error: Integrity check 'ok' not found in log file $LOG_FILE."
    cat "$LOG_FILE"
    exit 1
fi
echo "Integrity check 'ok' found in log."


echo "All checks passed!"
echo "Test successful."
exit 0
