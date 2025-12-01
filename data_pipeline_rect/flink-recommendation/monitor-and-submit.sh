#!/bin/bash

# Monitor script that auto-submits Flink job if it's not running
# This script monitors job status and automatically submits if job is stopped/cancelled
# Can be run as a daemon or via cron

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JOB_TYPE="${1:-user-activity}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"  # Check every 30 seconds
KAFKA_TOPIC=""
KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-kafka-1:29092}"

# Map job type to Kafka topic
case "$JOB_TYPE" in
    "user-activity")
        KAFKA_TOPIC="user_activities"
        ;;
    "user-photo-interaction")
        KAFKA_TOPIC="photo_interactions"
        ;;
    *)
        echo "Unknown job type: $JOB_TYPE"
        exit 1
        ;;
esac

echo "=========================================="
echo "  Flink Job Monitor & Auto-Submit"
echo "=========================================="
echo "Job Type: $JOB_TYPE"
echo "Kafka Topic: $KAFKA_TOPIC"
echo "Check Interval: ${CHECK_INTERVAL}s"
echo ""

# Function to check if there are new messages in Kafka topic
check_kafka_messages() {
    local topic=$1
    local bootstrap=$2
    
    # Get latest offset for the topic
    # This is a simple check - in production you might want more sophisticated logic
    if docker exec kafka-1 kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list "$bootstrap" \
        --topic "$topic" \
        --time -1 2>/dev/null | grep -q ":"; then
        return 0  # Topic exists and has partitions
    else
        return 1  # Topic doesn't exist or error
    fi
}

# Function to check if Flink job is running
is_job_running() {
    local job_name=$1
    local rest_url="${FLINK_REST_URL:-http://localhost:8082}"
    
    if ! curl -f -s "$rest_url/overview" > /dev/null 2>&1; then
        return 1  # Flink not accessible
    fi
    
    local jobs_json=$(curl -s "$rest_url/jobs" 2>/dev/null || echo '{"jobs":[]}')
    
    if command -v jq &> /dev/null; then
        local running=$(echo "$jobs_json" | jq -r ".jobs[]? | select(.name==\"$job_name\" and .status==\"RUNNING\") | .id" 2>/dev/null)
        if [ -n "$running" ]; then
            return 0  # Job is running
        fi
    else
        # Fallback: check if job name appears
        if echo "$jobs_json" | grep -q "$job_name"; then
            return 0
        fi
    fi
    
    return 1  # Job is not running
}

# Main monitoring loop
echo "Starting monitor loop..."
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Check if Kafka topic has messages
    if check_kafka_messages "$KAFKA_TOPIC" "$KAFKA_BOOTSTRAP"; then
        # Determine job name
        case "$JOB_TYPE" in
            "user-activity")
                JOB_NAME="User Activity Aggregation Job"
                ;;
            "user-photo-interaction")
                JOB_NAME="User-Photo Interaction Job"
                ;;
        esac
        
        # Check if job is running
        if ! is_job_running "$JOB_NAME"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Job '$JOB_NAME' is not running. Submitting..."
            bash "$SCRIPT_DIR/auto-submit-job.sh" "$JOB_TYPE"
            echo ""
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Job '$JOB_NAME' is running. Skipping."
        fi
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Kafka topic '$KAFKA_TOPIC' not accessible or doesn't exist"
    fi
    
    # Wait before next check
    sleep "$CHECK_INTERVAL"
done

