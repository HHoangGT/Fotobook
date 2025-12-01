#!/bin/bash

# Script để setup replication publication sau khi Rails đã tạo tables
# Chạy script này sau khi: rails db:migrate

set -e

# Configuration
POSTGRES_USER="${POSTGRES_USER:-fotobook}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
POSTGRES_DB="${POSTGRES_DB:-fotobook_development}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-fotobook-postgres}"

# Detect if running from WSL and get Windows host IP
if grep -qi microsoft /proc/version 2>/dev/null; then
    WINDOWS_HOST=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
    POSTGRES_HOST="${POSTGRES_HOST:-$WINDOWS_HOST}"
    POSTGRES_PORT="${POSTGRES_PORT:-5432}"
    echo "🔍 WSL detected. Using Windows host: $POSTGRES_HOST"
else
    POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
    POSTGRES_PORT="${POSTGRES_PORT:-5432}"
fi

# SQL script content
SQL_SCRIPT=$(cat <<'EOF'

-- Grant SELECT permissions trên tất cả tables hiện có
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO replication_user;

-- Grant usage trên sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO replication_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO replication_user;

-- Drop publication nếu đã tồn tại
DROP PUBLICATION IF EXISTS debezium_publication;

-- Tạo publication cho các tables cần capture
-- Lưu ý: Chỉ thêm tables nếu chúng tồn tại
DO $$
DECLARE
    tables_to_add TEXT[] := ARRAY[]::TEXT[];
    tbl TEXT;
    table_list TEXT[] := ARRAY['activity_logs', 'photo_likeables', 'albulm_likeables', 'photos', 'albums'];
BEGIN
    -- Kiểm tra từng table và thêm vào mảng nếu tồn tại
    FOREACH tbl IN ARRAY table_list
    LOOP
        IF EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = tbl
        ) THEN
            tables_to_add := array_append(tables_to_add, tbl);
            RAISE NOTICE 'Table % found, will be added to publication', tbl;
        ELSE
            RAISE NOTICE 'Table % does not exist, skipping', tbl;
        END IF;
    END LOOP;
    
    -- Tạo publication chỉ với các tables tồn tại
    IF array_length(tables_to_add, 1) > 0 THEN
        EXECUTE format('CREATE PUBLICATION debezium_publication FOR TABLE %s', 
                       array_to_string(tables_to_add, ', '));
        RAISE NOTICE 'Publication created with % tables', array_length(tables_to_add, 1);
    ELSE
        RAISE WARNING 'No tables found. Publication will not be created.';
    END IF;
END
$$;

-- Verify publication
SELECT 'Publication status:' as info;
SELECT pubname, puballtables FROM pg_publication WHERE pubname = 'debezium_publication';

SELECT 'Tables in publication:' as info;
SELECT tablename FROM pg_publication_tables WHERE pubname = 'debezium_publication';

EOF
)

echo "Setting up PostgreSQL replication for Debezium..."
echo "Database: $POSTGRES_DB"
echo "User: $POSTGRES_USER"
echo ""

# Check if psql is available
if command -v psql &> /dev/null; then
    echo "✅ Using psql client"
    echo "Connecting to: $POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
    echo ""
    
    PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB <<SQL
$SQL_SCRIPT
SQL

    EXIT_CODE=$?
    
elif command -v docker &> /dev/null; then
    echo "✅ Using Docker container: $POSTGRES_CONTAINER"
    echo "Note: Running SQL inside container"
    echo ""
    
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$"; then
        echo "❌ Error: Container '$POSTGRES_CONTAINER' is not running!"
        echo "Start it with: docker-compose up -d postgres"
        exit 1
    fi
    
    # Execute SQL directly via stdin - no file needed
    echo "$SQL_SCRIPT" | docker exec -i "${POSTGRES_CONTAINER}" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
    
    EXIT_CODE=$?
    
else
    echo "❌ Error: Neither 'psql' nor 'docker' command found!"
    echo ""
    echo "Please install one of the following:"
    echo "  1. PostgreSQL client: sudo apt install postgresql-client"
    echo "  2. Docker: Already installed (check PATH)"
    exit 1
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Replication setup completed successfully!"
    echo ""
    echo "To verify, run:"
    if command -v psql &> /dev/null; then
        echo "  psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c \"SELECT tablename FROM pg_publication_tables WHERE pubname = 'debezium_publication';\""
    else
        echo "  docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -c \"SELECT tablename FROM pg_publication_tables WHERE pubname = 'debezium_publication';\""
    fi
else
    echo ""
    echo "❌ Setup failed. Check error messages above."
    exit 1
fi