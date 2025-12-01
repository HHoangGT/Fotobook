#!/bin/bash

# Script để kiểm tra dữ liệu trong Redis

# Disable Git Bash path conversion
export MSYS_NO_PATHCONV=1

echo "=========================================="
echo "Redis Data Checker"
echo "=========================================="
echo ""

# Check Redis connection
echo "Step 1: Checking Redis connection..."
if ! docker exec redis redis-cli ping > /dev/null 2>&1; then
    echo "❌ Error: Redis is not accessible"
    echo "   Please make sure Redis container is running:"
    echo "   docker ps | grep redis"
    exit 1
fi
echo "✅ Redis is running"
echo ""

# Get all keys
echo "Step 2: Listing all keys in Redis..."
ALL_KEYS=$(docker exec redis redis-cli KEYS "*" 2>/dev/null)
KEY_COUNT=$(echo "$ALL_KEYS" | grep -v "^$" | wc -l | tr -d ' ')

if [ "$KEY_COUNT" -eq 0 ]; then
    echo "⚠️  No keys found in Redis"
    echo ""
    echo "Possible reasons:"
    echo "  1. Flink job hasn't processed any messages yet"
    echo "  2. No new messages in Kafka topic"
    echo "  3. Job is not running"
    echo ""
    echo "Check Flink job status:"
    echo "  docker exec flink-jobmanager /opt/flink/bin/flink list"
    echo ""
    echo "Check Flink job logs:"
    echo "  docker logs flink-jobmanager | tail -50"
    exit 0
fi

echo "✅ Found $KEY_COUNT key(s) in Redis"
echo ""

# Show keys by category
echo "Step 3: Keys by category..."
echo ""

# Photo like counts (1h)
echo "📸 Photo Like Count (1h):"
PHOTO_1H_KEYS=$(docker exec redis redis-cli KEYS "photo:like_count:1h:*" 2>/dev/null)
PHOTO_1H_COUNT=$(echo "$PHOTO_1H_KEYS" | grep -v "^$" | wc -l | tr -d ' ')
if [ "$PHOTO_1H_COUNT" -gt 0 ]; then
    echo "   Found $PHOTO_1H_COUNT key(s)"
    echo "$PHOTO_1H_KEYS" | head -5 | sed 's/^/   - /'
    if [ "$PHOTO_1H_COUNT" -gt 5 ]; then
        echo "   ... and $((PHOTO_1H_COUNT - 5)) more"
    fi
else
    echo "   No keys found"
fi
echo ""

# Photo like counts (24h)
echo "📸 Photo Like Count (24h):"
PHOTO_24H_KEYS=$(docker exec redis redis-cli KEYS "photo:like_count:24h:*" 2>/dev/null)
PHOTO_24H_COUNT=$(echo "$PHOTO_24H_KEYS" | grep -v "^$" | wc -l | tr -d ' ')
if [ "$PHOTO_24H_COUNT" -gt 0 ]; then
    echo "   Found $PHOTO_24H_COUNT key(s)"
    echo "$PHOTO_24H_KEYS" | head -5 | sed 's/^/   - /'
    if [ "$PHOTO_24H_COUNT" -gt 5 ]; then
        echo "   ... and $((PHOTO_24H_COUNT - 5)) more"
    fi
else
    echo "   No keys found"
fi
echo ""

# User engagement scores
echo "👤 User Engagement Scores:"
USER_KEYS=$(docker exec redis redis-cli KEYS "user:engagement_score:*" 2>/dev/null)
USER_COUNT=$(echo "$USER_KEYS" | grep -v "^$" | wc -l | tr -d ' ')
if [ "$USER_COUNT" -gt 0 ]; then
    echo "   Found $USER_COUNT key(s)"
    echo "$USER_KEYS" | head -5 | sed 's/^/   - /'
    if [ "$USER_COUNT" -gt 5 ]; then
        echo "   ... and $((USER_COUNT - 5)) more"
    fi
else
    echo "   No keys found"
fi
echo ""

# Show sample values
echo "Step 4: Sample values (first 3 keys)..."
echo ""
SAMPLE_KEYS=$(echo "$ALL_KEYS" | grep -v "^$" | head -3)
KEY_INDEX=0
for key in $SAMPLE_KEYS; do
    KEY_INDEX=$((KEY_INDEX + 1))
    echo "[$KEY_INDEX] Key: $key"
    VALUE=$(docker exec redis redis-cli GET "$key" 2>/dev/null)
    TTL=$(docker exec redis redis-cli TTL "$key" 2>/dev/null)
    
    # Try to format as JSON if possible
    if echo "$VALUE" | grep -q "^{"; then
        echo "   Value (JSON):"
        echo "$VALUE" | python -m json.tool 2>/dev/null || echo "$VALUE" | sed 's/^/      /'
    else
        echo "   Value: $VALUE"
    fi
    
    if [ "$TTL" -gt 0 ]; then
        HOURS=$((TTL / 3600))
        MINUTES=$(((TTL % 3600) / 60))
        echo "   TTL: ${HOURS}h ${MINUTES}m (expires in $TTL seconds)"
    elif [ "$TTL" -eq -1 ]; then
        echo "   TTL: No expiration"
    else
        echo "   TTL: Expired"
    fi
    echo ""
done

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total keys: $KEY_COUNT"
echo "  - Photo Like Count (1h): $PHOTO_1H_COUNT"
echo "  - Photo Like Count (24h): $PHOTO_24H_COUNT"
echo "  - User Engagement Scores: $USER_COUNT"
echo ""
echo "To view a specific key:"
echo "  docker exec redis redis-cli GET 'photo:like_count:1h:123'"
echo ""
echo "To view all keys:"
echo "  docker exec redis redis-cli KEYS '*'"
echo ""
echo "To view keys matching a pattern:"
echo "  docker exec redis redis-cli KEYS 'photo:like_count:1h:*'"
echo ""
echo "To view all values for photo like counts (1h):"
echo "  docker exec redis redis-cli --scan --pattern 'photo:like_count:1h:*' | head -5 | xargs -I {} docker exec redis redis-cli GET {}"
echo ""

