#!/bin/bash

# Script to register Avro schemas to Confluent Schema Registry

set -e

SCHEMA_REGISTRY_URL="${SCHEMA_REGISTRY_URL:-http://localhost:8081}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" =~ ^[A-Za-z]: ]]; then
    SCRIPT_DIR="/${SCRIPT_DIR:0:1,,}${SCRIPT_DIR:2}"
    SCRIPT_DIR="${SCRIPT_DIR//\\//}"
fi

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "$PROJECT_ROOT" =~ ^[A-Za-z]: ]]; then
    PROJECT_ROOT="/${PROJECT_ROOT:0:1,,}${PROJECT_ROOT:2}"
    PROJECT_ROOT="${PROJECT_ROOT//\\//}"
fi

SCHEMAS_DIR="${SCHEMAS_DIR:-$PROJECT_ROOT/debezium/schemas}"

if [[ "$SCHEMAS_DIR" =~ ^[A-Za-z]: ]]; then
    SCHEMAS_DIR="/${SCHEMAS_DIR:0:1,,}${SCHEMAS_DIR:2}"
    SCHEMAS_DIR="${SCHEMAS_DIR//\\//}"
fi

# Check if Python is available for JSON escaping
if command -v python3 &> /dev/null; then
    USE_PYTHON=true
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    USE_PYTHON=true
    PYTHON_CMD="python"
else
    USE_PYTHON=false
fi

# Check if jq is available
if command -v jq &> /dev/null; then
    USE_JQ=true
else
    USE_JQ=false
fi

echo "=== Registering Avro Schemas to Schema Registry ==="
echo "Schema Registry URL: $SCHEMA_REGISTRY_URL"
echo "Schemas Directory: $SCHEMAS_DIR"
echo ""

# Wait for Schema Registry
echo "Waiting for Schema Registry..."
MAX_RETRIES=30
RETRY_COUNT=0
until curl -f -s "$SCHEMA_REGISTRY_URL/subjects" > /dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ Error: Schema Registry is not responding"
    exit 1
  fi
  echo "Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done
echo "✅ Schema Registry is ready!"
echo ""

# Function to escape JSON using Python (simplified inline version)
# Function to escape JSON using Python (simplified inline version)
escape_json_python() {
    local json_file="$1"
    
    if [ "$USE_PYTHON" != true ]; then
        return 1
    fi
    
    # Create temp files for stdout and stderr
    local stdout_file=$(mktemp 2>/dev/null || echo "/tmp/schema_stdout_$$.txt")
    local stderr_file=$(mktemp 2>/dev/null || echo "/tmp/schema_stderr_$$.txt")
    
    # Use inline Python command with proper error handling
    # Convert Git Bash path to Windows path if needed
    $PYTHON_CMD -c "
import json
import sys
import os

def convert_path(path):
    '''Convert Git Bash path (/f/...) to Windows path (F:\...)'''
    if path.startswith('/'):
        # Git Bash path format: /f/path -> F:\path
        if len(path) >= 2 and path[1].isalpha():
            drive = path[1].upper()
            rest = path[2:].replace('/', '\\\\')
            return drive + ':' + rest
    return path

try:
    file_path = '$json_file'
    # Try original path first
    if not os.path.exists(file_path):
        # Try converting Git Bash path to Windows path
        win_path = convert_path(file_path)
        if os.path.exists(win_path):
            file_path = win_path
        else:
            # Try with forward slashes (Windows Python accepts both)
            alt_path = file_path.replace('/', '\\\\')
            if os.path.exists(alt_path):
                file_path = alt_path
            else:
                sys.stderr.write('File not found: ' + '$json_file' + '\n')
                sys.stderr.write('Tried: ' + file_path + ', ' + win_path + ', ' + alt_path + '\n')
                sys.exit(1)
    
    with open(file_path, 'r', encoding='utf-8') as f:
        schema = json.load(f)
    schema_str = json.dumps(schema, separators=(',', ':'))
    escaped = json.dumps(schema_str)
    print(escaped, end='')
    sys.exit(0)
except Exception as e:
    sys.stderr.write('Python error: ' + str(e) + '\n')
    sys.exit(1)
" > "$stdout_file" 2> "$stderr_file"
    
    local exit_code=$?
    local escaped_schema=""
    local error_msg=""
    
    if [ -f "$stdout_file" ]; then
        escaped_schema=$(cat "$stdout_file" 2>/dev/null)
    fi
    
    if [ -f "$stderr_file" ]; then
        error_msg=$(cat "$stderr_file" 2>/dev/null)
    fi
    
    # Cleanup
    rm -f "$stdout_file" "$stderr_file" 2>/dev/null
    
    if [ $exit_code -eq 0 ] && [ -n "$escaped_schema" ]; then
        echo "$escaped_schema"
        return 0
    else
        # Print error to stderr if any
        if [ -n "$error_msg" ]; then
            echo "  Python error: $error_msg" >&2
        fi
        return 1
    fi
}

# Function to register schema
register_schema() {
    local topic_name=$1
    local schema_file=$2
    local subject_name="${topic_name}-value"
    local escaped_schema=""
    
    if [ ! -f "$schema_file" ]; then
        echo "❌ Schema file not found: $schema_file"
        return 1
    fi
    
    echo "Registering schema for topic: $topic_name"
    echo "  Subject: $subject_name"
    echo "  File: $schema_file"
    
    # Use Python to properly escape JSON if available
    if [ "$USE_PYTHON" = true ]; then
        echo "  Processing with Python..."
        escaped_schema=$(escape_json_python "$schema_file")
        local python_exit=$?
        
        if [ $python_exit -ne 0 ] || [ -z "$escaped_schema" ]; then
            echo "  ⚠️  Python escaping failed, trying jq..."
            escaped_schema=""  # Clear any partial output
        else
            echo "  ✓ Schema processed successfully"
        fi
    fi
    
    # Fallback: use jq if available
    if [ -z "$escaped_schema" ] && [ "$USE_JQ" = true ]; then
        echo "  Processing with jq..."
        schema_content=$(cat "$schema_file")
        minified_schema=$(echo "$schema_content" | jq -c . 2>/dev/null)
        if [ $? -eq 0 ]; then
            escaped_schema=$(echo "$minified_schema" | jq -Rs . 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$escaped_schema" ]; then
                echo "  ✓ Schema processed successfully"
            else
                echo "  ❌ Failed to escape schema with jq"
                return 1
            fi
        else
            echo "  ❌ Failed to process schema with jq"
            return 1
        fi
    fi
    
    # If still no escaped schema, error
    if [ -z "$escaped_schema" ]; then
        echo "  ❌ Cannot process schema: need Python or jq"
        echo "     Install Python 3 or jq to continue"
        return 1
    fi
    
    # Validate that escaped_schema is valid JSON (starts and ends with quotes)
    if [[ ! "$escaped_schema" =~ ^\".*\"$ ]]; then
        echo "  ❌ Invalid escaped schema format (should be JSON string)"
        echo "  Debug output: ${escaped_schema:0:100}..."
        return 1
    fi
    
    # Build JSON payload
    json_payload="{\"schema\": $escaped_schema}"
    
    # Register schema with compatibility settings
    echo "  Sending to Schema Registry..."
    response=$(curl -s -w "\n%{http_code}" -X POST \
        "$SCHEMA_REGISTRY_URL/subjects/$subject_name/versions" \
        -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        -d "$json_payload" 2>&1)
    
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "  ✅ Registered successfully (HTTP $http_code)"
        if [ "$USE_JQ" = true ]; then
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        else
            echo "$body"
        fi
        
        # Set compatibility mode to BACKWARD
        echo "  Setting compatibility mode to BACKWARD..."
        compat_response=$(curl -s -w "\n%{http_code}" -X PUT \
            "$SCHEMA_REGISTRY_URL/config/$subject_name" \
            -H "Content-Type: application/vnd.schemaregistry.v1+json" \
            -d '{"compatibility": "BACKWARD"}' 2>&1)
        
        compat_code=$(echo "$compat_response" | tail -1)
        compat_body=$(echo "$compat_response" | sed '$d')
        if [ "$compat_code" -ge 200 ] && [ "$compat_code" -lt 300 ]; then
            echo "  ✅ Compatibility mode set to BACKWARD"
        else
            echo "  ⚠️  Failed to set compatibility mode (HTTP $compat_code)"
        fi
    else
        echo "  ❌ Registration failed (HTTP $http_code)"
        echo "  Response: $body"
        # Debug: show payload preview
        echo "  Debug payload preview: ${json_payload:0:200}..."
        return 1
    fi
    echo ""
}

# Register schemas
register_schema "user_activities" "$SCHEMAS_DIR/UserActivity.avsc"
register_schema "photo_interactions" "$SCHEMAS_DIR/PhotoInteraction.avsc"
register_schema "feed_views" "$SCHEMAS_DIR/FeedView.avsc"
register_schema "user_profiles_updates" "$SCHEMAS_DIR/UserProfileUpdate.avsc"

echo "=== Verifying Registered Schemas ==="
subjects=$(curl -s "$SCHEMA_REGISTRY_URL/subjects" 2>/dev/null)
if [ "$USE_JQ" = true ] && [ -n "$subjects" ]; then
    echo "$subjects" | jq '.' 2>/dev/null || echo "$subjects"
else
    echo "$subjects"
fi

echo ""
echo "✅ Schema registration completed!"