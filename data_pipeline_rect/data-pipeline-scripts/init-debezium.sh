# scripts/init-debezium.sh
#!/bin/bash

# Script to register all Debezium connectors
# Make sure Kafka Connect is running before executing this script

# Don't exit on error - we want to process all connectors even if some fail
set +e

# Get the directory where this script is located
# Works in both Unix/Linux and Windows Git Bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Convert Windows path to Unix path if running in Git Bash
if [[ "$SCRIPT_DIR" =~ ^[A-Za-z]: ]]; then
    # Windows path (C:\...), convert to /c/... format for Git Bash
    SCRIPT_DIR="/${SCRIPT_DIR:0:1,,}${SCRIPT_DIR:2}"
    SCRIPT_DIR="${SCRIPT_DIR//\\//}"
fi

# Get project root (one level up from data-pipeline-scripts directory)
# Check if we're in data-pipeline-scripts or scripts directory
if [[ "$SCRIPT_DIR" == *"/data-pipeline-scripts" ]] || [[ "$SCRIPT_DIR" == *"/scripts" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    # If script is at root, use current directory
    PROJECT_ROOT="$SCRIPT_DIR"
fi

# Convert Windows path to Unix path for project root if needed
if [[ "$PROJECT_ROOT" =~ ^[A-Za-z]: ]]; then
    PROJECT_ROOT="/${PROJECT_ROOT:0:1,,}${PROJECT_ROOT:2}"
    PROJECT_ROOT="${PROJECT_ROOT//\\//}"
fi

# Default connector directory
DEFAULT_CONNECTOR_DIR="$PROJECT_ROOT/debezium/connectors"
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
CONNECTOR_DIR="${CONNECTOR_DIR:-$DEFAULT_CONNECTOR_DIR}"

# Convert Windows path to Unix path for connector dir if needed
if [[ "$CONNECTOR_DIR" =~ ^[A-Za-z]: ]]; then
    CONNECTOR_DIR="/${CONNECTOR_DIR:0:1,,}${CONNECTOR_DIR:2}"
    CONNECTOR_DIR="${CONNECTOR_DIR//\\//}"
fi

# Check if jq is available (optional, for pretty JSON output)
if command -v jq &> /dev/null; then
    USE_JQ=true
else
    USE_JQ=false
    echo "⚠️  Note: 'jq' not found. JSON output will not be formatted."
    echo "   Install with: sudo apt install jq (Linux/WSL) or choco install jq (Windows)"
    echo ""
fi

echo "Initializing Debezium connectors..."
echo "Script Directory: $SCRIPT_DIR"
echo "Project Root: $PROJECT_ROOT"
echo "Kafka Connect URL: $KAFKA_CONNECT_URL"
echo "Connector Directory: $CONNECTOR_DIR"
echo ""

# Wait for Kafka Connect to be ready
echo "Waiting for Kafka Connect to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
until curl -f -s "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ Error: Kafka Connect is not responding after $MAX_RETRIES retries"
    echo "   Make sure Kafka Connect is running at $KAFKA_CONNECT_URL"
    exit 1
  fi
  echo "Waiting for Kafka Connect... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 5
done
echo "✅ Kafka Connect is ready!"
echo ""

# Check if connector directory exists
if [ ! -d "$CONNECTOR_DIR" ]; then
    echo "❌ Error: Connector directory not found: $CONNECTOR_DIR"
    echo ""
    echo "Debug information:"
    echo "  Current working directory: $(pwd)"
    echo "  Script directory: $SCRIPT_DIR"
    echo "  Project root: $PROJECT_ROOT"
    echo "  Expected connector dir: $CONNECTOR_DIR"
    echo ""
    echo "You can set CONNECTOR_DIR environment variable:"
    echo "  export CONNECTOR_DIR=/path/to/debezium/connectors"
    exit 1
fi

# Count connector files
connector_count=$(find "$CONNECTOR_DIR" -name "*.json" -type f 2>/dev/null | wc -l)
if [ "$connector_count" -eq 0 ]; then
    echo "❌ Error: No connector JSON files found in $CONNECTOR_DIR"
    echo ""
    echo "Directory contents:"
    ls -la "$CONNECTOR_DIR" || echo "Cannot list directory"
    exit 1
fi

echo "Found $connector_count connector file(s)"
echo ""

# List all connector files
echo "Connector files to process:"
for connector_file in "$CONNECTOR_DIR"/*.json; do
    if [ -f "$connector_file" ]; then
        echo "  - $(basename "$connector_file")"
    fi
done
echo ""

# Register each connector
success_count=0
fail_count=0
failed_connectors=()

for connector_file in "$CONNECTOR_DIR"/*.json; do
  # Check if file exists (handle case where no .json files match)
  if [ ! -f "$connector_file" ]; then
    continue
  fi
  
  connector_name=$(basename "$connector_file" .json)
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Processing: $connector_name"
  echo "File: $connector_file"
  
  # Validate JSON file before processing
  if [ "$USE_JQ" = true ]; then
    if ! jq empty "$connector_file" 2>/dev/null; then
      echo "  ❌ Invalid JSON file!"
      ((fail_count++))
      failed_connectors+=("$connector_name (Invalid JSON)")
      echo ""
      continue
    fi
  else
    # Basic JSON validation without jq - check if file starts with { and ends with }
    first_char=$(head -c 1 "$connector_file" 2>/dev/null | tr -d '[:space:]')
    if [ "$first_char" != "{" ]; then
      echo "  ❌ Invalid JSON file (doesn't start with '{')!"
      ((fail_count++))
      failed_connectors+=("$connector_name (Invalid JSON format)")
      echo ""
      continue
    fi
  fi
  
  # Check if connector already exists
  # Extract connector name from JSON file (not from filename)
  json_connector_name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$connector_file" 2>/dev/null | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")
  if [ -n "$json_connector_name" ]; then
    connector_check_name="$json_connector_name"
  else
    connector_check_name="$connector_name"
  fi
  
  if curl -f -s "$KAFKA_CONNECT_URL/connectors/$connector_check_name" > /dev/null 2>&1; then
    echo "  ⚠️  Connector already exists. Updating..."
    
    # Extract only the config part from JSON file for PUT request
    temp_config=$(mktemp 2>/dev/null || echo /tmp/config_$$.json)
    if [ "$USE_JQ" = true ]; then
      jq '.config' "$connector_file" > "$temp_config" 2>/dev/null
    else
      # Extract config using sed/awk (fallback when jq is not available)
      # This is a simple approach - extract everything between "config": { and matching }
      sed -n '/"config"[[:space:]]*:[[:space:]]*{/,/^[[:space:]]*}[[:space:]]*$/p' "$connector_file" | sed '1s/.*"config"[[:space:]]*:[[:space:]]*{/{/' | sed '$s/}[[:space:]]*$/}/' > "$temp_config" 2>/dev/null || {
        # If sed fails, try with python
        python3 -c "import json, sys; data = json.load(open('$connector_file')); print(json.dumps(data['config']))" > "$temp_config" 2>/dev/null || {
          # Last resort: use the whole file (may fail but better than nothing)
          cat "$connector_file" > "$temp_config"
        }
      }
    fi
    
    temp_response=$(mktemp 2>/dev/null || echo /tmp/response_$$)
    http_code=$(curl -s -w "\n%{http_code}" -X PUT "$KAFKA_CONNECT_URL/connectors/$connector_check_name/config" \
      -H "Content-Type: application/json" \
      -d @"$temp_config" \
      -o "$temp_response" 2>&1)
    
    rm -f "$temp_config" 2>/dev/null
    
    # Extract HTTP code from output (curl -w puts it last)
    if [[ "$http_code" =~ ^[0-9]+$ ]]; then
      actual_code="$http_code"
    else
      # If http_code contains other output, extract the code
      actual_code=$(echo "$http_code" | tail -1 | grep -oE '[0-9]{3}' || echo "000")
    fi
    
    if [ "$actual_code" -ge 200 ] && [ "$actual_code" -lt 300 ]; then
      echo "  ✅ Updated successfully (HTTP $actual_code)"
      if [ "$USE_JQ" = true ]; then
        cat "$temp_response" 2>/dev/null | jq '.' 2>/dev/null || cat "$temp_response"
      else
        cat "$temp_response" 2>/dev/null
      fi
      ((success_count++))
    else
      echo "  ❌ Update failed (HTTP $actual_code)"
      echo "  Response body:"
      cat "$temp_response" 2>/dev/null | head -20
      ((fail_count++))
      failed_connectors+=("$connector_name (Update failed: HTTP $actual_code)")
    fi
    rm -f "$temp_response" 2>/dev/null
    
  else
    echo "  ➕ Creating new connector..."
    
    temp_response=$(mktemp 2>/dev/null || echo /tmp/response_$$)
    # Use verbose mode to see what's being sent
    http_code=$(curl -s -w "\n%{http_code}" -X POST "$KAFKA_CONNECT_URL/connectors" \
      -H "Content-Type: application/json" \
      -d @"$connector_file" \
      -o "$temp_response" 2>&1)
    
    # Extract HTTP code
    if [[ "$http_code" =~ ^[0-9]+$ ]]; then
      actual_code="$http_code"
    else
      actual_code=$(echo "$http_code" | tail -1 | grep -oE '[0-9]{3}' || echo "000")
    fi
    
    if [ "$actual_code" -ge 200 ] && [ "$actual_code" -lt 300 ]; then
      echo "  ✅ Created successfully (HTTP $actual_code)"
      if [ "$USE_JQ" = true ]; then
        cat "$temp_response" 2>/dev/null | jq '.' 2>/dev/null || cat "$temp_response"
      else
        cat "$temp_response" 2>/dev/null
      fi
      ((success_count++))
    else
      echo "  ❌ Creation failed (HTTP $actual_code)"
      echo "  Full response:"
      cat "$temp_response" 2>/dev/null
      echo ""
      echo "  Connector config (first 20 lines):"
      head -20 "$connector_file" 2>/dev/null || echo "Cannot read file"
      ((fail_count++))
      failed_connectors+=("$connector_name (Creation failed: HTTP $actual_code)")
      # Don't exit - continue with next connector
    fi
    rm -f "$temp_response" 2>/dev/null
  fi
  
  echo ""
  sleep 2
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Summary:"
echo "  ✅ Successful: $success_count"
echo "  ❌ Failed: $fail_count"
echo ""

if [ ${#failed_connectors[@]} -gt 0 ]; then
    echo "Failed connectors:"
    for failed in "${failed_connectors[@]}"; do
        echo "  - $failed"
    done
    echo ""
fi

if [ "$fail_count" -gt 0 ]; then
    echo "⚠️  Some connectors failed to create. Check errors above."
    echo ""
    echo "To debug, try registering a failed connector manually:"
    echo "  curl -X POST $KAFKA_CONNECT_URL/connectors \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d @debezium/connectors/<connector-name>.json"
    echo ""
fi

echo "Listing all connectors:"
connectors=$(curl -s "$KAFKA_CONNECT_URL/connectors" 2>/dev/null)
if [ "$USE_JQ" = true ] && [ -n "$connectors" ]; then
  echo "$connectors" | jq '.' 2>/dev/null || echo "$connectors"
else
  echo "$connectors"
fi

echo ""
echo "Checking connector statuses:"
for connector_file in "$CONNECTOR_DIR"/*.json; do
  if [ -f "$connector_file" ]; then
    connector_name=$(basename "$connector_file" .json)
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Status of: $connector_name"
    
    if curl -f -s "$KAFKA_CONNECT_URL/connectors/$connector_name" > /dev/null 2>&1; then
      status=$(curl -s "$KAFKA_CONNECT_URL/connectors/$connector_name/status" 2>/dev/null)
      if [ "$USE_JQ" = true ] && [ -n "$status" ]; then
        echo "$status" | jq '.' 2>/dev/null || echo "$status"
      else
        echo "$status"
      fi
    else
      echo "  ⚠️  Connector does not exist"
    fi
  fi
done

echo ""
if [ "$fail_count" -eq 0 ] && [ "$success_count" -gt 0 ]; then
    echo "✅ All connectors initialized successfully!"
elif [ "$success_count" -gt 0 ]; then
    echo "⚠️  Done with some issues. Review the output above."
else
    echo "❌ No connectors were created. Please check the errors above."
    exit 1
fi