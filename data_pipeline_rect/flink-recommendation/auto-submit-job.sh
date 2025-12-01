#!/bin/bash

# Script to automatically submit Flink job if not running
# This script will check if job is running, and submit if not
# Job will only process new messages (latest offset)

# Don't exit on error - we want to handle errors ourselves
set +e

# Disable Git Bash path conversion for all docker commands
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JOB_TYPE="${1:-user-activity}"
FLINK_REST_URL="${FLINK_REST_URL:-http://localhost:8082}"
# Use /tmp path to avoid volume mount issues
TMP_JAR_FILE="/tmp/flink-recommendation-jobs-1.0.0.jar"
JOB_NAME=""

# Map job type to job name
case "$JOB_TYPE" in
    "user-activity")
        JOB_NAME="User Activity Aggregation Job"
        ;;
    "user-photo-interaction")
        JOB_NAME="User-Photo Interaction Job"
        ;;
    *)
        echo "Unknown job type: $JOB_TYPE"
        exit 1
        ;;
esac

echo "=========================================="
echo "  Auto Submit Flink Job"
echo "=========================================="
echo "Job Type: $JOB_TYPE"
echo "Job Name: $JOB_NAME"
echo "Flink REST URL: $FLINK_REST_URL"
echo ""

# Check if Flink JobManager is accessible
echo "Step 1: Checking Flink JobManager..."
if ! curl -f -s "$FLINK_REST_URL/overview" > /dev/null 2>&1; then
    echo "❌ Flink JobManager is not accessible at $FLINK_REST_URL"
    echo "   Make sure Flink is running: docker ps | grep flink-jobmanager"
    exit 1
fi
echo "✅ Flink JobManager is accessible"
echo ""

# Check if job is already running
echo "Step 2: Checking if job is already running..."
JOBS_JSON=$(curl -s "$FLINK_REST_URL/jobs" 2>/dev/null || echo '{"jobs":[]}')

# Check if jq is available
if command -v jq &> /dev/null; then
    RUNNING_JOBS=$(echo "$JOBS_JSON" | jq -r '.jobs[]? | select(.status=="RUNNING") | .name' 2>/dev/null || echo "")
    if echo "$RUNNING_JOBS" | grep -q "$JOB_NAME"; then
        echo "✅ Job '$JOB_NAME' is already running"
        echo ""
        echo "Job details:"
        echo "$JOBS_JSON" | jq -r ".jobs[]? | select(.name==\"$JOB_NAME\" and .status==\"RUNNING\") | \"  ID: \(.id)\n  Status: \(.status)\n  Start Time: \(.start-time)\"" 2>/dev/null || echo "  (Unable to parse job details)"
        exit 0
    fi
else
    # Fallback: check if job name appears in response
    if echo "$JOBS_JSON" | grep -q "$JOB_NAME"; then
        echo "⚠️  Job '$JOB_NAME' might be running (jq not available for detailed check)"
        echo "   Install jq for better job detection: sudo apt install jq"
        echo "   Or check manually at: $FLINK_REST_URL/#/overview"
        exit 0
    fi
fi

echo "ℹ️  Job '$JOB_NAME' is not running"
echo ""

# Check if JAR file exists locally
echo "Step 3: Checking JAR file..."
LOCAL_JAR="target/flink-recommendation-jobs-1.0.0.jar"
TMP_JAR_FILE="/tmp/flink-recommendation-jobs-1.0.0.jar"

if [ ! -f "$LOCAL_JAR" ]; then
    echo "⚠️  JAR file not found locally: $LOCAL_JAR"
    echo "   Building JAR..."
    
    # Build the project
    if [ ! -f "$LOCAL_JAR" ]; then
        echo "   Building project..."
        
        # Function to convert Windows path to Docker-compatible path
        convert_path_for_docker() {
            local path="$1"
            if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
                if command -v pwd &> /dev/null; then
                    local win_path=$(cd "$path" && pwd -W 2>/dev/null || echo "")
                    if [ -n "$win_path" ]; then
                        if [[ "$win_path" =~ ^([A-Za-z]):(.*)$ ]]; then
                            local drive="${BASH_REMATCH[1]}"
                            drive=$(echo "$drive" | tr '[:upper:]' '[:lower:]')
                            local rest="${BASH_REMATCH[2]}"
                            rest="${rest//\\//}"
                            echo "/${drive}${rest}"
                            return
                        fi
                    fi
                fi
                if [[ "$path" =~ ^[A-Za-z]: ]]; then
                    local drive="${path:0:1}"
                    drive=$(echo "$drive" | tr '[:upper:]' '[:lower:]')
                    path="/${drive}${path:2}"
                fi
                path="${path//\\//}"
            fi
            echo "$path"
        }
        
        # Check if Maven is available
        if command -v mvn &> /dev/null; then
            mvn clean package -DskipTests
        else
            echo "   Using Docker Maven..."
            DOCKER_SCRIPT_DIR=$(convert_path_for_docker "$SCRIPT_DIR")
            DOCKER_M2_DIR=""
            if [ -n "$HOME" ] && [ -d "$HOME/.m2" ]; then
                DOCKER_M2_DIR=$(convert_path_for_docker "$HOME/.m2")
            fi
            
            # Disable Git Bash path conversion for Docker commands
            if [ -n "$DOCKER_M2_DIR" ]; then
                MSYS_NO_PATHCONV=1 docker run --rm \
                    -v "${DOCKER_SCRIPT_DIR}:/usr/src/mymaven" \
                    -v "${DOCKER_M2_DIR}:/root/.m2" \
                    -w /usr/src/mymaven \
                    maven:3.8-openjdk-11 \
                    mvn clean package -DskipTests
            else
                MSYS_NO_PATHCONV=1 docker run --rm \
                    -v "${DOCKER_SCRIPT_DIR}:/usr/src/mymaven" \
                    -w /usr/src/mymaven \
                    maven:3.8-openjdk-11 \
                    mvn clean package -DskipTests
            fi
        fi
        
        if [ $? -ne 0 ]; then
            echo "❌ Build failed!"
            exit 1
        fi
    fi
    
    if [ $? -ne 0 ]; then
        echo "❌ Build failed!"
        exit 1
    fi
fi

# Always copy JAR to /tmp in container (to ensure latest version)
echo "   Copying JAR to container /tmp..."
docker cp "$LOCAL_JAR" flink-jobmanager:"$TMP_JAR_FILE"
if [ $? -ne 0 ]; then
    echo "❌ Failed to copy JAR to container!"
    exit 1
fi
echo "✅ JAR file ready in container"
echo ""

# Submit the job
echo "Step 4: Submitting Flink job..."
echo "   Note: Job will start from LATEST offset (will skip old messages)"
echo ""

# Submit job
echo "   Submitting job (this may take a moment)..."
# Disable Git Bash path conversion for docker exec
# Submit with explicit timeout to prevent hanging
if command -v timeout &> /dev/null; then
    SUBMIT_OUTPUT=$(timeout 30 docker exec flink-jobmanager /opt/flink/bin/flink run \
        -d \
        -c com.fotobook.recommendation.flink.FlinkRecommendationJobs \
        "$TMP_JAR_FILE" \
        "$JOB_TYPE" 2>&1)
    SUBMIT_EXIT_CODE=$?
    # Timeout exit code is 124, but job might still be submitted
    if [ $SUBMIT_EXIT_CODE -eq 124 ]; then
        echo "   ⚠️  Submit command timed out (30s), checking if job was submitted..."
        SUBMIT_EXIT_CODE=0  # Treat as potential success, will verify below
    fi
else
    # Fallback: run without timeout
    SUBMIT_OUTPUT=$(docker exec flink-jobmanager /opt/flink/bin/flink run \
        -d \
        -c com.fotobook.recommendation.flink.FlinkRecommendationJobs \
        "$TMP_JAR_FILE" \
        "$JOB_TYPE" 2>&1)
    SUBMIT_EXIT_CODE=$?
fi

# Check if job was submitted successfully
# Success indicators: "Job has been submitted" or "JobID" in output
# Note: Java warnings are normal and don't indicate failure
if echo "$SUBMIT_OUTPUT" | grep -q "Job has been submitted\|JobID"; then
    echo "✅ Job submitted successfully!"
    echo ""
    # Filter out warnings and show only important info
    echo "$SUBMIT_OUTPUT" | grep -v "^WARNING\|^Illegal reflective" | grep -v "^$" || echo "$SUBMIT_OUTPUT"
    echo ""
    
    # Extract JobID if available
    JOB_ID=$(echo "$SUBMIT_OUTPUT" | grep -oP "JobID \K[a-f0-9]+" | head -1)
    if [ -n "$JOB_ID" ]; then
        echo "   Job ID: $JOB_ID"
    fi
    
    # Wait a moment and verify job started
    echo "   Waiting for job to start..."
    sleep 5
    
    # Check if job is running
    JOB_LIST=$(docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null || echo "")
    if echo "$JOB_LIST" | grep -q "RUNNING\|RESTARTING"; then
        echo "✅ Job is running!"
        echo "$JOB_LIST" | grep -E "RUNNING|RESTARTING" || true
    else
        echo "⚠️  Job submitted but not yet running (may be starting up)"
        echo "$JOB_LIST"
    fi
    
    echo ""
    echo "Job will start processing NEW messages only (latest offset)"
    echo "Check Flink UI at: $FLINK_REST_URL"
    echo "View running jobs: $FLINK_REST_URL/#/overview"
elif [ $SUBMIT_EXIT_CODE -eq 0 ]; then
    # Exit code is 0 but no JobID found - might still be success, check job list
    echo "⚠️  Submit command completed but no JobID found in output"
    echo "   Checking job status..."
    sleep 3
    JOB_LIST=$(docker exec flink-jobmanager /opt/flink/bin/flink list 2>/dev/null || echo "")
    if echo "$JOB_LIST" | grep -q "RUNNING\|RESTARTING"; then
        echo "✅ Job is running!"
        echo "$JOB_LIST"
    else
        echo "❌ Job not found in running jobs"
        echo "Output:"
        echo "$SUBMIT_OUTPUT" | grep -v "^WARNING\|^Illegal reflective"
        exit 1
    fi
else
    echo "❌ Failed to submit job!"
    echo ""
    echo "Error output:"
    echo "$SUBMIT_OUTPUT" | grep -v "^WARNING\|^Illegal reflective" || echo "$SUBMIT_OUTPUT"
    exit 1
fi

