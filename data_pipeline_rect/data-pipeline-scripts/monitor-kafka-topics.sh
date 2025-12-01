#!/bin/bash

# Monitoring script for Kafka topics - lag, throughput, error rates

set -e

KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka-1}"

# Check if running inside Docker
if docker ps | grep -q "$KAFKA_CONTAINER"; then
    KAFKA_CMD="docker exec $KAFKA_CONTAINER"
    BOOTSTRAP="kafka-1:29092,kafka-2:29092,kafka-3:29092"
else
    KAFKA_CMD=""
    BOOTSTRAP="$KAFKA_BOOTSTRAP"
fi

echo "=== Kafka Topics Monitoring ==="
echo "Bootstrap: $BOOTSTRAP"
echo "Timestamp: $(date)"
echo ""

# Topics to monitor
TOPICS=("user_activities" "photo_interactions" "feed_views" "user_profiles_updates")

# Function to get consumer group lag
get_consumer_lag() {
    local group=$1
    echo "Consumer Group: $group"
    $KAFKA_CMD kafka-consumer-groups --bootstrap-server "$BOOTSTRAP" \
        --describe --group "$group" 2>/dev/null || echo "  No active consumers"
    echo ""
}

# Function to get topic metrics
get_topic_metrics() {
    local topic=$1
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Topic: $topic"
    
    # Get topic description
    echo "Partition Details:"
    $KAFKA_CMD kafka-topics --bootstrap-server "$BOOTSTRAP" \
        --describe --topic "$topic" 2>/dev/null || echo "  Topic not found"
    
    echo ""
    echo "Message Count (approximate):"
    $KAFKA_CMD kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list "$BOOTSTRAP" \
        --topic "$topic" \
        --time -1 2>/dev/null | awk -F: '{sum+=$3} END {print "  Total messages: " sum}' || echo "  Unable to get count"
    
    echo ""
}

# Function to check DLQ
check_dlq() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Dead Letter Queue: recommendation_dlq"
    $KAFKA_CMD kafka-topics --bootstrap-server "$BOOTSTRAP" \
        --describe --topic "recommendation_dlq" 2>/dev/null || echo "  DLQ topic not found"
    
    echo ""
    echo "DLQ Message Count:"
    $KAFKA_CMD kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list "$BOOTSTRAP" \
        --topic "recommendation_dlq" \
        --time -1 2>/dev/null | awk -F: '{sum+=$3} END {print "  Total DLQ messages: " sum}' || echo "  Unable to get count"
    echo ""
}

# Main monitoring
for topic in "${TOPICS[@]}"; do
    get_topic_metrics "$topic"
done

check_dlq

echo "=== Consumer Groups ==="
echo "Listing all consumer groups..."
$KAFKA_CMD kafka-consumer-groups --bootstrap-server "$BOOTSTRAP" --list 2>/dev/null || echo "Unable to list consumer groups"
echo ""

echo "✅ Monitoring completed!"