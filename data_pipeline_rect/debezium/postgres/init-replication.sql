-- debezium/postgres/init-replication.sql
-- Script này sẽ chạy tự động khi PostgreSQL container khởi động lần đầu

-- Tạo replication user
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replication_user') THEN
    CREATE ROLE replication_user WITH REPLICATION LOGIN PASSWORD 'replication_password';
  END IF;
END
$$;

-- Grant permissions cho replication user
GRANT CONNECT ON DATABASE fotobook_development TO replication_user;
GRANT USAGE ON SCHEMA public TO replication_user;

-- Note: Tables permissions và publication sẽ được setup sau khi Rails tạo tables
-- Chạy script: scripts/setup-postgres-replication.sh sau khi rails db:migrate