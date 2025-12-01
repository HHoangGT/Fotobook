#!/bin/bash

# Complete Rebuild Script for All Services
# This script will:
# 1. Stop all services
# 2. Remove all containers, volumes, and networks
# 3. Clean up Schema Registry subjects
# 4. Rebuild and start all services
# 5. Setup connectors and topics

set -e

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Configuration
SCHEMA_REGISTRY_URL="${SCHEMA_REGISTRY_URL:-http://localhost:8081}"
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Flags
KEEP_DATA=false
SKIP_SETUP=false
AUTO_CONFIRM=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-data|-k)
            KEEP_DATA=true
            shift
            ;;
        --skip-setup|-s)
            SKIP_SETUP=true
            shift
            ;;
        --yes|-y)
            AUTO_CONFIRM=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--keep-data] [--skip-setup] [--yes]"
            echo ""
            echo "Options:"
            echo "  --keep-data, -k    Keep PostgreSQL, Grafana, and Prometheus data volumes"
            echo "  --skip-setup, -s   Skip connector and topic setup after rebuild"
            echo "  --yes, -y          Auto-confirm all prompts"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "  Complete Rebuild - All Services"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Stop all services (Docker Compose)"
echo "  2. Remove all containers"
if [ "$KEEP_DATA" = false ]; then
    echo "  3. Remove all volumes (⚠️  POSTGRES DATA WILL BE LOST!)"
else
    echo "  3. Keep data volumes (PostgreSQL, Grafana, Prometheus)"
fi
echo "  4. Remove networks"
echo "  5. Clean Schema Registry subjects"
echo "  6. Rebuild and start all services"
if [ "$SKIP_SETUP" = false ]; then
    echo "  7. Setup Kafka topics"
    echo "  8. Register Debezium connectors"
fi
echo ""

if [ "$KEEP_DATA" = false ]; then
    echo -e "${RED}⚠️  WARNING: All data will be deleted!${NC}"
    echo "   - PostgreSQL database will be empty"
    echo "   - Grafana dashboards will be reset"
    echo "   - Prometheus metrics will be cleared"
    echo ""
fi

if [ "$AUTO_CONFIRM" = false ]; then
    read -p "Continue? (type 'yes' to confirm): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled."
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 1: Stop All Services${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}Stopping Flink cluster...${NC}"
cd flink-recommendation
docker-compose -f docker-compose.flink.yml down 2>/dev/null || true
cd ..

echo -e "${CYAN}Stopping main services...${NC}"
docker-compose down 2>/dev/null || true

echo -e "${GREEN}✓ All services stopped${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 2: Remove Containers${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Remove containers related to our project
echo -e "${CYAN}Removing containers...${NC}"
docker ps -a --filter "name=fotobook" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=kafka" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=zookeeper" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=schema-registry" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=kafka-connect" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=debezium" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=flink" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=prometheus" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=grafana" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -a --filter "name=redis" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true

echo -e "${GREEN}✓ Containers removed${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 3: Remove Volumes${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

if [ "$KEEP_DATA" = true ]; then
    echo -e "${YELLOW}⚠ Keeping data volumes (--keep-data flag)${NC}"
    echo "  Keeping: postgres-data, grafana-data, prometheus-data"
else
    echo -e "${CYAN}Removing volumes...${NC}"
    
    # Remove volumes
    docker volume rm postgres-data 2>/dev/null || true
    docker volume rm prometheus-data 2>/dev/null || true
    docker volume rm grafana-data 2>/dev/null || true
    docker volume rm flink-checkpoints 2>/dev/null || true
    
    # Remove any orphaned volumes from project
    docker volume ls --filter "name=fotobook" -q | xargs -r docker volume rm 2>/dev/null || true
    docker volume ls --filter "name=kafka" -q | xargs -r docker volume rm 2>/dev/null || true
    docker volume ls --filter "name=flink" -q | xargs -r docker volume rm 2>/dev/null || true
    
    echo -e "${GREEN}✓ Volumes removed${NC}"
fi
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 4: Remove Networks${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}Removing networks...${NC}"
docker network rm kafka-network 2>/dev/null || true
docker network prune -f >/dev/null 2>&1 || true

echo -e "${GREEN}✓ Networks removed${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 5: Clean Schema Registry${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Try to clean Schema Registry if it's accessible
if curl -f -s "$SCHEMA_REGISTRY_URL/subjects" > /dev/null 2>&1; then
    echo -e "${CYAN}Cleaning Schema Registry subjects...${NC}"
    
    SUBJECTS=$(curl -s "$SCHEMA_REGISTRY_URL/subjects" 2>/dev/null || echo "[]")
    
    if [ -n "$SUBJECTS" ] && [ "$SUBJECTS" != "[]" ]; then
        for subject in $(echo "$SUBJECTS" | jq -r '.[]' 2>/dev/null || echo ""); do
            if [ -n "$subject" ] && [ "$subject" != "null" ]; then
                echo "  Deleting subject: $subject"
                curl -s -X DELETE "$SCHEMA_REGISTRY_URL/subjects/$subject" > /dev/null 2>&1 || true
            fi
        done
        echo -e "  ${GREEN}✓ Schema Registry cleaned${NC}"
    else
        echo -e "  ${YELLOW}⚠ No subjects found${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ Schema Registry not accessible (may not be running yet)${NC}"
fi
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 6: Rebuild and Start Services${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Rebuild kafka-connect image if needed
echo -e "${CYAN}Rebuilding kafka-connect image...${NC}"
docker-compose build kafka-connect 2>&1 | grep -E "(Step|Successfully|Using cache)" || echo "  (Using existing image)"

echo ""
echo -e "${CYAN}Creating network...${NC}"
docker network create kafka-network 2>/dev/null || echo "  Network already exists"

echo ""
echo -e "${CYAN}Starting all services...${NC}"
docker-compose up -d

echo ""
echo -e "${CYAN}Waiting for services to be ready...${NC}"
echo "  Waiting for Zookeeper..."
for i in {1..30}; do
    if docker exec zookeeper nc -z localhost 2181 2>/dev/null; then
        echo -e "  ${GREEN}✓ Zookeeper ready${NC}"
        break
    fi
    sleep 1
done

echo "  Waiting for Kafka brokers..."
for i in {1..60}; do
    if docker exec kafka-1 kafka-broker-api-versions --bootstrap-server kafka-1:29092 2>/dev/null; then
        echo -e "  ${GREEN}✓ Kafka brokers ready${NC}"
        break
    fi
    sleep 2
done

echo "  Waiting for Schema Registry..."
for i in {1..30}; do
    if curl -f -s "$SCHEMA_REGISTRY_URL/subjects" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Schema Registry ready${NC}"
        break
    fi
    sleep 2
done

echo "  Waiting for Kafka Connect..."
for i in {1..60}; do
    if curl -f -s "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Kafka Connect ready${NC}"
        break
    fi
    sleep 2
done

echo ""
echo -e "${CYAN}Starting Flink cluster...${NC}"
cd flink-recommendation
docker-compose -f docker-compose.flink.yml up -d
cd ..

echo ""
echo -e "${GREEN}✓ All services started${NC}"
echo ""

if [ "$SKIP_SETUP" = true ]; then
    echo -e "${YELLOW}⚠ Skipping connector and topic setup (--skip-setup flag)${NC}"
    echo ""
    echo "To setup manually:"
    echo "  ./data-pipeline-scripts/setup-kafka-topics.sh"
    echo "  ./data-pipeline-scripts/init-debezium.sh"
    exit 0
fi

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 7: Setup Kafka Topics${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

if [ -f "data-pipeline-scripts/setup-kafka-topics.sh" ]; then
    echo -e "${CYAN}Running setup-kafka-topics.sh...${NC}"
    bash data-pipeline-scripts/setup-kafka-topics.sh
    echo ""
else
    echo -e "${YELLOW}⚠ setup-kafka-topics.sh not found, skipping...${NC}"
fi

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 8: Register Debezium Connectors${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Wait a bit more for Kafka Connect to be fully ready
sleep 5

if [ -f "data-pipeline-scripts/init-debezium.sh" ]; then
    echo -e "${CYAN}Running init-debezium.sh...${NC}"
    bash data-pipeline-scripts/init-debezium.sh
    echo ""
else
    echo -e "${YELLOW}⚠ init-debezium.sh not found, skipping...${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 9: Verification${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}Checking service status...${NC}"
docker-compose ps

echo ""
echo -e "${CYAN}Checking connectors...${NC}"
CONNECTORS=$(curl -s "$KAFKA_CONNECT_URL/connectors" 2>/dev/null || echo "[]")
if [ -n "$CONNECTORS" ] && [ "$CONNECTORS" != "[]" ]; then
    echo "$CONNECTORS" | jq -r '.[]' 2>/dev/null || echo "$CONNECTORS"
else
    echo "  No connectors registered yet"
fi

echo ""
echo -e "${GREEN}✅ Rebuild completed successfully!${NC}"
echo ""
echo "📊 Service URLs:"
echo "  - Flink Web UI: http://localhost:8082"
echo "  - Grafana: http://localhost:3000"
echo "  - Prometheus: http://localhost:9090"
echo "  - Kafka UI: http://localhost:8090"
echo "  - Schema Registry: http://localhost:8081"
echo "  - Kafka Connect: http://localhost:8083"
echo ""
echo "Next steps:"
echo "  1. Check service status: docker-compose ps"
echo "  2. Check connectors: ./checking-scripts/check-debezium.sh all"
echo "  3. Check topics: ./checking-scripts/check-kafka.sh --list"
echo "  4. Setup PostgreSQL replication slots if needed"
echo ""
