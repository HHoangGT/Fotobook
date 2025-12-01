# scripts/health-check-debezium.sh
#!/bin/bash

# Health check script for Debezium CDC pipeline

set -e

KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
DEBEZIUM_UI_URL="${DEBEZIUM_UI_URL:-http://localhost:8080}"
KAFKA_UI_URL="${KAFKA_UI_URL:-http://localhost:8090}"

# Check if jq is available
if command -v jq &> /dev/null; then
    USE_JQ=true
else
    USE_JQ=false
    echo "⚠️  Note: 'jq' not found. Some JSON parsing will be limited."
    echo "   Install with: sudo apt install jq (Linux/WSL) or choco install jq (Windows)"
    echo ""
fi

echo "=== Debezium CDC Health Check ==="
echo ""

# Check Kafka Connect
echo "1. Checking Kafka Connect..."
if curl -f -s "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; then
  echo "   ✓ Kafka Connect is running"
  echo "   URL: $KAFKA_CONNECT_URL"
else
  echo "   ✗ Kafka Connect is not accessible"
  echo "   URL: $KAFKA_CONNECT_URL"
  exit 1
fi

# Check Debezium UI
echo ""
echo "2. Checking Debezium UI..."
if curl -f -s "$DEBEZIUM_UI_URL" > /dev/null 2>&1; then
  echo "   ✓ Debezium UI is running"
  echo "   URL: $DEBEZIUM_UI_URL"
  echo "   ℹ️  Access the web interface at: $DEBEZIUM_UI_URL"
else
  echo "   ⚠ Debezium UI is not accessible"
  echo "   URL: $DEBEZIUM_UI_URL"
  echo "   ℹ️  Make sure Debezium UI container is running: docker ps | grep debezium-ui"
fi

# Check Kafka UI
echo ""
echo "3. Checking Kafka UI..."
if curl -f -s "$KAFKA_UI_URL" > /dev/null 2>&1; then
  echo "   ✓ Kafka UI is running"
  echo "   URL: $KAFKA_UI_URL"
  echo "   ℹ️  Access the web interface at: $KAFKA_UI_URL"
else
  echo "   ⚠ Kafka UI is not accessible"
  echo "   URL: $KAFKA_UI_URL"
  echo "   ℹ️  Make sure Kafka UI container is running: docker ps | grep kafka-ui"
fi

# Check connectors
echo ""
echo "4. Checking Connectors..."
connectors_json=$(curl -s "$KAFKA_CONNECT_URL/connectors" 2>/dev/null || echo "[]")

# Debug: Show raw JSON
if [ "$DEBUG" = "true" ]; then
  echo "   Debug - Raw connectors JSON: $connectors_json"
fi

if [ -z "$connectors_json" ] || [ "$connectors_json" = "[]" ]; then
  echo "   ⚠ No connectors found"
else
  # Parse connectors array
  if [ "$USE_JQ" = true ]; then
    connectors=$(echo "$connectors_json" | jq -r '.[]' 2>/dev/null || echo "")
  else
    # Simple parsing without jq - extract strings from array
    # Remove brackets and quotes, split by comma
    connectors=$(echo "$connectors_json" | sed 's/^\[//' | sed 's/\]$//' | sed 's/"//g' | sed 's/,/\n/g' | sed 's/^ *//' | sed 's/ *$//' | grep -v '^$' | grep -v '^\[' | grep -v '^\]')
  fi
  
  if [ -z "$connectors" ]; then
    echo "   ⚠ No connectors found (could not parse or empty)"
    if [ "$DEBUG" = "true" ]; then
      echo "   Debug - Parsed connectors: <empty>"
    fi
  else
    connector_count=0
    running_count=0
    failed_count=0
    
    # Process each connector
    while IFS= read -r connector || [ -n "$connector" ]; do
      # Clean up connector name
      connector=$(echo "$connector" | sed 's/^ *//' | sed 's/ *$//' | tr -d '\n\r' | grep -v '^$')
      
      if [ -z "$connector" ]; then
        continue
      fi
      
      connector_count=$((connector_count + 1))
      echo "   Checking: $connector..."
      
      status_json=$(curl -s "$KAFKA_CONNECT_URL/connectors/$connector/status" 2>/dev/null || echo "")
      
      if [ -z "$status_json" ]; then
        echo "     ⚠ Could not get status"
        continue
      fi
      
      # Extract status
      if [ "$USE_JQ" = true ]; then
        status=$(echo "$status_json" | jq -r '.connector.state' 2>/dev/null || echo "UNKNOWN")
        task_count=$(echo "$status_json" | jq '.tasks | length' 2>/dev/null || echo "0")
      else
        # Extract state field manually
        status=$(echo "$status_json" | grep -oP '"connector":\{[^}]*"state":"\K[^"]*' | head -1 || echo "UNKNOWN")
        if [ -z "$status" ] || [ "$status" = "UNKNOWN" ]; then
          status=$(echo "$status_json" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "UNKNOWN")
        fi
        task_count=$(echo "$status_json" | grep -o '"tasks":\[' | wc -l || echo "0")
      fi
      
      # Display status
      case "$status" in
        "RUNNING")
          echo "     ✓ $connector: RUNNING"
          running_count=$((running_count + 1))
          
          # Try to get task states if available
          if [ "$USE_JQ" = true ] && [ "$task_count" -gt 0 ]; then
            task_states=$(echo "$status_json" | jq -r '.tasks[].state' 2>/dev/null || echo "")
            for task_state in $task_states; do
              if [ "$task_state" = "RUNNING" ]; then
                echo "       ✓ Task: RUNNING"
              elif [ "$task_state" = "FAILED" ]; then
                echo "       ✗ Task: FAILED"
                failed_count=$((failed_count + 1))
              else
                echo "       ⚠ Task: $task_state"
              fi
            done
          fi
          ;;
        "FAILED")
          echo "     ✗ $connector: FAILED"
          failed_count=$((failed_count + 1))
          
          # Try to extract error message
          if [ "$USE_JQ" = true ]; then
            error_msg=$(echo "$status_json" | jq -r '.connector.trace // .tasks[0].trace // ""' 2>/dev/null | head -3 || echo "")
          else
            error_msg=$(echo "$status_json" | grep -oP '"trace":"\K[^"]*' | head -1 || echo "")
          fi
          if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
            echo "       Error: $(echo "$error_msg" | head -c 100)"
          fi
          ;;
        *)
          echo "     ⚠ $connector: $status"
          ;;
      esac
    done <<< "$connectors"
    
    echo ""
    echo "   Summary: $connector_count connector(s) - $running_count running, $failed_count failed"
  fi
fi

# Check Kafka topics
echo ""
echo "5. Checking Kafka Topics..."
topics=(
  "fotobook.activity_logs"
  "fotobook.photo_likeables"
  "fotobook.album_likeables"
  "fotobook.photos"
  "fotobook.albums"
)

topics_found=0
topics_missing=0

# Try using Docker to check topics (preferred method)
if command -v docker &> /dev/null; then
  kafka_container=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^kafka-1$" | head -1 || echo "")
  
  if [ -n "$kafka_container" ]; then
    echo "   Checking via Docker container: $kafka_container"
    bootstrap_server="kafka-1:29092"
    
    # Get all topics
    all_topics=$(docker exec "$kafka_container" kafka-topics \
      --bootstrap-server "$bootstrap_server" \
      --list 2>/dev/null | tr '\n' ' ' || echo "")
    
    if [ -n "$all_topics" ]; then
      for topic in "${topics[@]}"; do
        # Check if topic exists in the list
        if echo "$all_topics" | grep -qw "$topic"; then
          # Get partition count
          partition_info=$(docker exec "$kafka_container" kafka-topics \
            --bootstrap-server "$bootstrap_server" \
            --describe --topic "$topic" 2>/dev/null || echo "")
          partition_count=$(echo "$partition_info" | grep -c "Partition:" || echo "?")
          echo "   ✓ $topic exists ($partition_count partitions)"
          topics_found=$((topics_found + 1))
        else
          echo "   ✗ $topic does not exist yet"
          topics_missing=$((topics_missing + 1))
        fi
      done
      
      if [ "$topics_missing" -gt 0 ]; then
        echo ""
        echo "   ℹ️  Note: Topics may be created automatically when connectors start processing data"
      fi
    else
      echo "   ⚠ Could not list topics from container"
      echo "   Expected topics: ${topics[*]}"
    fi
  else
    echo "   ⚠ Kafka container 'kafka-1' not found"
    echo "   Expected topics: ${topics[*]}"
  fi

# Fallback: Try local kafka-topics.sh if Docker not available
elif command -v kafka-topics.sh &> /dev/null; then
  echo "   Using local kafka-topics.sh"
  for topic in "${topics[@]}"; do
    if kafka-topics.sh --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null | grep -q "^$topic$"; then
      partition_count=$(kafka-topics.sh --bootstrap-server "$KAFKA_BOOTSTRAP" --describe --topic "$topic" 2>/dev/null | grep -c "Partition:" || echo "0")
      echo "   ✓ $topic exists ($partition_count partitions)"
      topics_found=$((topics_found + 1))
    else
      echo "   ✗ $topic does not exist"
      topics_missing=$((topics_missing + 1))
    fi
  done
else
  echo "   ⚠ Cannot check topics (Docker and kafka-topics.sh not available)"
  echo "   Expected topics: ${topics[*]}"
  echo ""
  echo "   To check manually:"
  echo "     docker exec kafka-1 kafka-topics --bootstrap-server kafka-1:29092 --list"
fi