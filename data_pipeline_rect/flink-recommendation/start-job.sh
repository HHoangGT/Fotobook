#!/bin/bash

# Script đơn giản để submit Flink job một lần và để nó chạy 24/7
# Job sẽ tự động restart nếu bị lỗi (đã cấu hình restart strategy)
# Job sẽ tự động nhận và xử lý message mới từ Kafka

# Disable Git Bash path conversion
export MSYS_NO_PATHCONV=1

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Job type (default: user-activity)
JOB_TYPE="${1:-user-activity}"

# Flink configuration
FLINK_REST_URL="${FLINK_REST_URL:-http://localhost:8082}"
JAR_FILE="/tmp/flink-recommendation-jobs-1.0.0.jar"

echo "=========================================="
echo "Flink Job Starter - Submit Once, Run 24/7"
echo "=========================================="
echo ""
echo "Job Type: $JOB_TYPE"
echo "Flink REST URL: $FLINK_REST_URL"
echo ""

# Check if Flink is running
echo "Step 1: Checking Flink cluster..."
if ! curl -f -s "$FLINK_REST_URL/overview" > /dev/null 2>&1; then
    echo "❌ Error: Flink cluster is not accessible at $FLINK_REST_URL"
    echo "   Please make sure Flink containers are running:"
    echo "   docker-compose -f docker-compose.flink.yml up -d"
    exit 1
fi
echo "✅ Flink cluster is running"
echo ""

# Check if JAR exists locally
echo "Step 2: Checking JAR file..."
LOCAL_JAR="$SCRIPT_DIR/target/flink-recommendation-jobs-1.0.0.jar"
if [ ! -f "$LOCAL_JAR" ]; then
    echo "❌ Error: JAR file not found: $LOCAL_JAR"
    echo "   Please build the project first:"
    echo "   bash build-and-submit.sh $JOB_TYPE"
    exit 1
fi
echo "✅ JAR file found: $LOCAL_JAR"
echo ""

# Check if job is already running
echo "Step 3: Checking if job is already running..."
JOBS_JSON=$(curl -s "$FLINK_REST_URL/jobs" 2>/dev/null || echo '{"jobs":[]}')

JOB_NAME=""
case "$JOB_TYPE" in
    "user-activity")
        JOB_NAME="User Activity Aggregation Job"
        ;;
    "user-photo-interaction")
        JOB_NAME="User-Photo Interaction Job"
        ;;
    *)
        JOB_NAME="*"
        ;;
esac

# Check for running jobs using Flink CLI (more reliable)
RUNNING_JOBS=$(docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null | grep -E "RUNNING|RESTARTING" | grep "$JOB_NAME" || echo "")

if [ -n "$RUNNING_JOBS" ]; then
    echo "⚠️  Job '$JOB_NAME' is already running!"
    echo ""
    echo "Running jobs:"
    echo "$RUNNING_JOBS"
    echo ""
    echo "Job is already running 24/7. No need to submit again."
    echo "Check Flink UI: $FLINK_REST_URL/#/overview"
    echo ""
    echo "To cancel existing jobs, run:"
    echo "  docker exec flink-jobmanager /opt/flink/bin/flink list"
    echo "  docker exec flink-jobmanager /opt/flink/bin/flink cancel <JobID>"
    exit 0
fi
echo "✅ No running job found, will submit new job"
echo ""

# Copy JAR to container
echo "Step 4: Copying JAR to Flink container..."

# Function to convert Windows path for Docker (Git Bash compatible)
convert_path_for_docker() {
    local path="$1"
    
    # Check if we're on Windows (Git Bash/MSYS)
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
        # Try to get Windows path using pwd -W (Git Bash)
        if command -v pwd &> /dev/null; then
            local dir_path=$(dirname "$path")
            local filename=$(basename "$path")
            local win_path=$(cd "$dir_path" 2>/dev/null && pwd -W 2>/dev/null || echo "")
            if [ -n "$win_path" ] && [[ "$win_path" =~ ^[A-Za-z]: ]]; then
                # Convert backslashes to forward slashes and append filename
                echo "${win_path//\\//}/$filename"
                return
            fi
        fi
        
        # Fallback: try to convert from Git Bash format /f/path
        if [[ "$path" =~ ^/[a-z]/ ]]; then
            # /f/path -> F:/path (Windows format with forward slashes)
            local drive="${path:1:1}"
            drive=$(echo "$drive" | tr '[:lower:]' '[:upper:]')
            local rest="${path:2}"
            echo "${drive}:${rest}"
            return
        elif [[ "$path" =~ ^[A-Za-z]: ]]; then
            # Already Windows format, convert backslashes to forward slashes
            echo "${path//\\//}"
            return
        fi
    fi
    
    # Return as-is for Unix systems
    echo "$path"
}

# Convert path for Docker
DOCKER_JAR_PATH=$(convert_path_for_docker "$LOCAL_JAR")

# Try copying with converted path (MSYS_NO_PATHCONV is already exported)
# Use relative path from script directory to avoid path conversion issues
RELATIVE_JAR="target/$(basename "$LOCAL_JAR")"

# Try multiple methods
COPY_SUCCESS=false

# Method 1: Try with converted absolute path
if docker cp "$DOCKER_JAR_PATH" flink-jobmanager:"$JAR_FILE" 2>/dev/null; then
    echo "✅ JAR copied to container"
    COPY_SUCCESS=true
# Method 2: Try with original absolute path
elif docker cp "$LOCAL_JAR" flink-jobmanager:"$JAR_FILE" 2>/dev/null; then
    echo "✅ JAR copied to container"
    COPY_SUCCESS=true
# Method 3: Try with relative path from script directory
elif docker cp "$RELATIVE_JAR" flink-jobmanager:"$JAR_FILE" 2>/dev/null; then
    echo "✅ JAR copied to container (using relative path)"
    COPY_SUCCESS=true
# Method 4: Use stdin (works in all cases but slower)
else
    echo "   Trying alternative method (using stdin)..."
    if docker exec -i flink-jobmanager sh -c "cat > $JAR_FILE" < "$LOCAL_JAR" 2>/dev/null; then
        echo "✅ JAR copied to container (using stdin)"
        COPY_SUCCESS=true
    fi
fi

if [ "$COPY_SUCCESS" = false ]; then
    echo "❌ Error: Failed to copy JAR to container"
    echo "   Local JAR: $LOCAL_JAR"
    echo "   Converted path: $DOCKER_JAR_PATH"
    echo "   Relative path: $RELATIVE_JAR"
    echo ""
    echo "   Please try manually:"
    echo "   docker cp \"$LOCAL_JAR\" flink-jobmanager:$JAR_FILE"
    exit 1
fi
echo ""

# Submit job
echo "Step 5: Submitting Flink job..."
echo "   Job will run 24/7 and automatically restart if errors occur"
echo "   Job will automatically process new messages from Kafka"
echo ""

SUBMIT_OUTPUT=$(docker exec flink-jobmanager /opt/flink/bin/flink run \
    -d \
    -c com.fotobook.recommendation.flink.FlinkRecommendationJobs \
    "$JAR_FILE" \
    "$JOB_TYPE" 2>&1)

SUBMIT_EXIT_CODE=$?

# Filter out Java warnings for cleaner output
CLEAN_OUTPUT=$(echo "$SUBMIT_OUTPUT" | grep -v "WARNING:.*reflective access" || echo "$SUBMIT_OUTPUT")

echo "$CLEAN_OUTPUT"
echo ""

# Check if submission was successful
if echo "$SUBMIT_OUTPUT" | grep -q "Job has been submitted\|JobID"; then
    JOB_ID=$(echo "$SUBMIT_OUTPUT" | grep -oP "JobID \K[a-f0-9]+" || echo "unknown")
    echo "✅ Job submitted successfully!"
    echo "   Job ID: $JOB_ID"
    echo ""
    
    # Wait a bit for job to start
    echo "Waiting for job to start..."
    sleep 5
    
    # Check job status
    JOB_LIST=$(docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null || echo "")
    if echo "$JOB_LIST" | grep -q "RUNNING\|RESTARTING"; then
        echo "✅ Job is now running!"
        echo "$JOB_LIST" | grep -E "RUNNING|RESTARTING" || true
    else
        echo "⚠️  Job submitted but not yet running (may be starting up)"
        echo "$JOB_LIST"
    fi
    
    echo ""
    echo "=========================================="
    echo "✅ Job is now running 24/7!"
    echo "=========================================="
    echo ""
    echo "Job Configuration:"
    echo "  - Restart Strategy: 10 attempts with 30s delay"
    echo "  - Checkpointing: Every 1 minute (EXACTLY_ONCE)"
    echo "  - Kafka Offset: LATEST (only new messages)"
    echo "  - Auto-restart: Enabled"
    echo ""
    echo "Monitoring:"
    echo "  - Flink UI: $FLINK_REST_URL/#/overview"
    echo "  - Job Details: $FLINK_REST_URL/#/job/$JOB_ID"
    echo ""
    echo "The job will:"
    echo "  ✅ Run continuously 24/7"
    echo "  ✅ Automatically restart if errors occur"
    echo "  ✅ Automatically process new messages from Kafka"
    echo "  ✅ Skip old messages (LATEST offset)"
    echo ""
    echo "To stop the job:"
    echo "  docker exec flink-jobmanager /opt/flink/bin/flink cancel $JOB_ID"
    echo ""
    
elif [ $SUBMIT_EXIT_CODE -eq 0 ]; then
    echo "⚠️  Submit command completed but no JobID found"
    echo "   Checking job status..."
    sleep 3
    JOB_LIST=$(docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null || echo "")
    echo "$JOB_LIST"
    
    if echo "$JOB_LIST" | grep -q "RUNNING\|RESTARTING"; then
        echo ""
        echo "✅ Job appears to be running!"
    else
        echo ""
        echo "❌ Job submission may have failed"
        echo "   Check Flink logs: docker logs flink-jobmanager"
        exit 1
    fi
else
    echo "❌ Error: Failed to submit job"
    echo "   Exit code: $SUBMIT_EXIT_CODE"
    echo "   Check Flink logs: docker logs flink-jobmanager"
    exit 1
fi

