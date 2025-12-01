#!/bin/bash

# Complete setup script for recommendation system topics and schemas

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" =~ ^[A-Za-z]: ]]; then
    SCRIPT_DIR="/${SCRIPT_DIR:0:1,,}${SCRIPT_DIR:2}"
    SCRIPT_DIR="${SCRIPT_DIR//\\//}"
fi

echo "=== Recommendation System Setup ==="
echo ""

# Step 1: Create topics
echo "Step 1: Creating Kafka topics..."
bash "$SCRIPT_DIR/setup-kafka-topics.sh"
echo ""

# Step 2: Register schemas
echo "Step 2: Registering Avro schemas..."
bash "$SCRIPT_DIR/register-schemas.sh"
echo ""

# Step 3: Verify setup
echo "Step 3: Verifying setup..."
echo "Topics:"
docker exec kafka-1 kafka-topics --bootstrap-server kafka-1:29092 --list | grep -E "(user_activities|photo_interactions|feed_views|user_profiles_updates)" || true

echo ""
echo "Schemas:"
curl -s http://localhost:8081/subjects | jq '.' 2>/dev/null || curl -s http://localhost:8081/subjects

echo ""
echo "✅ Setup completed!"
echo ""
echo "Next steps:"
echo "1. Update Debezium connectors to use Avro converter"
echo "2. Setup normalization transformers"
echo "3. Configure Flink consumers for Phase 4"