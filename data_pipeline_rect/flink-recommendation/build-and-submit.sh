#!/bin/bash

# Script to build Flink job and submit to cluster
# Uses Docker Maven if local Maven is not available
# Windows/Git Bash compatible

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JOB_TYPE="${1:-user-activity}"

echo "=========================================="
echo "  Build and Submit Flink Job"
echo "=========================================="
echo "Job Type: $JOB_TYPE"
echo ""

# Function to convert Windows path to Docker-compatible path
# On Windows, Docker Desktop needs Windows path format
convert_path_for_docker() {
    local path="$1"
    
    # Check if we're on Windows (Git Bash/MSYS)
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
        # Try to get Windows path using pwd -W (Git Bash)
        if command -v pwd &> /dev/null; then
            local win_path=$(cd "$path" 2>/dev/null && pwd -W 2>/dev/null || echo "")
            if [ -n "$win_path" ] && [[ "$win_path" =~ ^[A-Za-z]: ]]; then
                # Convert backslashes to forward slashes for Docker
                # Docker Desktop on Windows accepts both C:\path and C:/path
                # But forward slashes work more reliably
                echo "${win_path//\\//}"
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
    
    # For non-Windows or if conversion failed, return as-is
    echo "$path"
}

# Check if Maven is available
if command -v mvn &> /dev/null; then
    echo "Using local Maven..."
    USE_DOCKER_MAVEN=false
else
    echo "Maven not found locally. Using Docker Maven..."
    USE_DOCKER_MAVEN=true
    
    # Convert paths for Docker on Windows
    DOCKER_SCRIPT_DIR=$(convert_path_for_docker "$SCRIPT_DIR")
    DOCKER_M2_DIR=""
    if [ -n "$HOME" ] && [ -d "$HOME/.m2" ]; then
        DOCKER_M2_DIR=$(convert_path_for_docker "$HOME/.m2")
    fi
    
    echo "   Docker script dir: $DOCKER_SCRIPT_DIR"
    if [ -n "$DOCKER_M2_DIR" ]; then
        echo "   Docker M2 dir: $DOCKER_M2_DIR"
    fi
fi

# Build the project
echo "Step 1: Building Flink job..."
if [ "$USE_DOCKER_MAVEN" = true ]; then
    echo "   Using Docker Maven with path: $DOCKER_SCRIPT_DIR"
    if [ -n "$DOCKER_M2_DIR" ]; then
        echo "   Maven cache dir: $DOCKER_M2_DIR"
    fi
    
    # Disable Git Bash path conversion for Docker commands
    # MSYS_NO_PATHCONV=1 prevents Git Bash from converting paths
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
else
    mvn clean package -DskipTests
fi

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful!"
echo ""

# Check if JAR file exists
JAR_FILE="target/flink-recommendation-jobs-1.0.0.jar"
if [ ! -f "$JAR_FILE" ]; then
    echo "❌ JAR file not found: $JAR_FILE"
    exit 1
fi

echo "Step 2: Copying JAR to Flink container..."
# Copy JAR to Flink jobmanager
docker cp "$JAR_FILE" flink-jobmanager:/opt/flink/usrlib/flink-recommendation-jobs.jar

if [ $? -ne 0 ]; then
    echo "❌ Failed to copy JAR to container!"
    exit 1
fi

echo "✅ JAR copied successfully!"
echo ""

# Submit the job
echo "Step 3: Submitting Flink job..."
docker exec flink-jobmanager /opt/flink/bin/flink run \
    -d \
    -c com.fotobook.recommendation.flink.FlinkRecommendationJobs \
    /opt/flink/usrlib/flink-recommendation-jobs.jar \
    "$JOB_TYPE"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Job submitted successfully!"
    echo ""
    echo "Check Flink UI at: http://localhost:8082"
    echo "View running jobs: http://localhost:8082/#/overview"
else
    echo ""
    echo "❌ Failed to submit job!"
    exit 1
fi