#!/bin/bash

# Check Kafka Topics and Messages
# Usage: ./check-kafka.sh [topic-name] [--latest N] [--consume]

set -e

KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka-1}"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  Kafka Topics Check"
echo "=========================================="
echo ""

# Check if Kafka container is running
if ! docker ps | grep -q "$KAFKA_CONTAINER"; then
    echo "✗ Kafka container not running: $KAFKA_CONTAINER"
    exit 1
fi

KAFKA_CMD="docker exec $KAFKA_CONTAINER kafka-topics --bootstrap-server $KAFKA_CONTAINER:29092"
CONSUMER_CMD="docker exec -i $KAFKA_CONTAINER kafka-console-consumer --bootstrap-server $KAFKA_CONTAINER:29092"

# List all topics
if [ -z "$1" ] || [ "$1" == "--list" ]; then
    echo -e "${CYAN}1. All Kafka topics:${NC}"
    $KAFKA_CMD --list
    echo ""
    
    echo -e "${CYAN}2. Recommendation system topics:${NC}"
    RECO_TOPICS=("user_activities" "photo_interactions" "feed_views" "user_profiles_updates")
    for topic in "${RECO_TOPICS[@]}"; do
        if $KAFKA_CMD --list | grep -q "^${topic}$"; then
            echo -e "${GREEN}✓${NC} $topic"
        else
            echo "✗ $topic (not found)"
        fi
    done
    echo ""
    
    echo -e "${CYAN}3. Debezium topics:${NC}"
    DEBEZIUM_TOPICS=("fotobook.photos" "fotobook.albums" "fotobook.photo_likeables" "fotobook.album_likeables")
    for topic in "${DEBEZIUM_TOPICS[@]}"; do
        if $KAFKA_CMD --list | grep -q "^${topic}$"; then
            echo -e "${GREEN}✓${NC} $topic"
        else
            echo "✗ $topic (not found)"
        fi
    done
    echo ""
fi

# Check specific topic
if [ -n "$1" ] && [ "$1" != "--list" ]; then
    TOPIC="$1"
    
    if ! $KAFKA_CMD --list | grep -q "^${TOPIC}$"; then
        echo "✗ Topic not found: $TOPIC"
        exit 1
    fi
    
    echo -e "${CYAN}Topic: $TOPIC${NC}"
    echo ""
    
    # Topic details
    echo -e "${CYAN}1. Topic details:${NC}"
    $KAFKA_CMD --describe --topic "$TOPIC"
    echo ""
    
    # Message count (approximate)
    echo -e "${CYAN}2. Message offsets:${NC}"
    docker exec $KAFKA_CONTAINER kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list $KAFKA_CONTAINER:29092 \
        --topic "$TOPIC" \
        --time -1 2>/dev/null | head -5
    echo ""
    
    # Get latest messages
    if [ "$2" == "--latest" ] && [ -n "$3" ]; then
        COUNT="$3"
        echo -e "${CYAN}3. Latest $COUNT messages:${NC}"
        $CONSUMER_CMD \
            --topic "$TOPIC" \
            --from-beginning \
            --max-messages "$COUNT" \
            --timeout-ms 5000 2>/dev/null | while read -r line; do
            echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $line"
        done
        echo ""
    elif [ "$2" == "--consume" ]; then
        echo -e "${CYAN}3. Consuming messages (Ctrl+C to stop):${NC}"
        $CONSUMER_CMD \
            --topic "$TOPIC" \
            --from-beginning 2>/dev/null | while read -r line; do
            echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $line"
        done
    else
        echo -e "${CYAN}3. Latest 5 messages:${NC}"
        timeout 5 $CONSUMER_CMD \
            --topic "$TOPIC" \
            --from-beginning \
            --max-messages 5 \
            --timeout-ms 5000 2>/dev/null | while read -r line; do
            echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $line"
        done || echo "No messages found or timeout"
        echo ""
        echo "Usage for more messages:"
        echo "  ./check-kafka.sh $TOPIC --latest 10"
        echo "  ./check-kafka.sh $TOPIC --consume  # Continuous consumption"
    fi
fi

echo ""
echo "Done!"