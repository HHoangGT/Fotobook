#!/bin/bash

# Script to create Kafka topics for recommendation system
# Topics with proper partitions and replication factors

set -e

KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka-1}"

# Check if running inside Docker or locally
if docker ps | grep -q "$KAFKA_CONTAINER"; then
    echo "Running inside Docker environment"
    KAFKA_CMD="docker exec $KAFKA_CONTAINER kafka-topics"
    BOOTSTRAP="kafka-1:29092,kafka-2:29092,kafka-3:29092"
else
    echo "Running locally (assuming kafka-topics in PATH)"
    KAFKA_CMD="kafka-topics"
    BOOTSTRAP="$KAFKA_BOOTSTRAP"
fi

echo "=== Creating Kafka Topics for Recommendation System ==="
echo "Bootstrap servers: $BOOTSTRAP"
echo ""

# Function to create topic
create_topic() {
    local topic_name=$1
    local partitions=$2
    local replication=$3
    local config_string=$4
    
    echo "Creating topic: $topic_name"
    echo "  Partitions: $partitions"
    echo "  Replication: $replication"
    
    # Build base command
    local cmd="$KAFKA_CMD --bootstrap-server \"$BOOTSTRAP\" --create --topic \"$topic_name\" --partitions \"$partitions\" --replication-factor \"$replication\""
    
    # Add configs if provided
    if [ -n "$config_string" ]; then
        echo "  Config: $config_string"
        # Parse config string (format: key1=val1,key2=val2,...)
        IFS=',' read -ra CONFIGS <<< "$config_string"
        for config in "${CONFIGS[@]}"; do
            cmd="$cmd --config \"$config\""
        done
    fi
    
    cmd="$cmd --if-not-exists"
    
    # Execute command
    eval $cmd
    
    if [ $? -eq 0 ]; then
        echo "  ✅ Created successfully"
    else
        echo "  ❌ Failed to create"
        return 1
    fi
    echo ""
}

# 1. user_activities topic
create_topic "user_activities" 10 3 \
    "min.insync.replicas=2,retention.ms=604800000,compression.type=lz4"

# 2. photo_interactions topic
create_topic "photo_interactions" 15 3 \
    "min.insync.replicas=2,retention.ms=604800000,compression.type=lz4"

# 3. feed_views topic
create_topic "feed_views" 8 3 \
    "min.insync.replicas=2,retention.ms=604800000,compression.type=lz4"

# 4. user_profiles_updates topic
create_topic "user_profiles_updates" 5 3 \
    "min.insync.replicas=2,retention.ms=604800000,compression.type=lz4"

# 5. Dead Letter Queue topic
create_topic "recommendation_dlq" 3 3 \
    "min.insync.replicas=2,retention.ms=2592000000,compression.type=lz4"

echo "=== Verifying Topics ==="
$KAFKA_CMD --bootstrap-server "$BOOTSTRAP" --list | grep -E "(user_activities|photo_interactions|feed_views|user_profiles_updates|recommendation_dlq)" || true

echo ""
echo "=== Topic Details ==="
for topic in user_activities photo_interactions feed_views user_profiles_updates recommendation_dlq; do
    echo ""
    echo "Topic: $topic"
    $KAFKA_CMD --bootstrap-server "$BOOTSTRAP" --describe --topic "$topic" 2>/dev/null || echo "  Topic not found"
done

echo ""
echo "✅ Topic setup completed!"