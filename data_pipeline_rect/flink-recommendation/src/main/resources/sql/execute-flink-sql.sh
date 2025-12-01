#!/bin/bash

# Script to execute Flink SQL queries
# Usage: ./execute-flink-sql.sh <sql-file>

set -e

FLINK_SQL_CLIENT="${FLINK_SQL_CLIENT:-/opt/flink/bin/sql-client.sh}"
SQL_FILE="${1:-}"

if [ -z "$SQL_FILE" ]; then
    echo "Usage: $0 <sql-file>"
    echo "Example: $0 src/main/resources/sql/user_activity_aggregation.sql"
    exit 1
fi

if [ ! -f "$SQL_FILE" ]; then
    echo "Error: SQL file not found: $SQL_FILE"
    exit 1
fi

echo "=== Executing Flink SQL: $SQL_FILE ==="

# Start SQL client in embedded mode and execute SQL file
$FLINK_SQL_CLIENT embedded <<EOF
-- Execute SQL file
EXECUTE STATEMENT SET BEGIN
$(cat "$SQL_FILE")
END;
EOF

echo "✅ SQL execution completed!"