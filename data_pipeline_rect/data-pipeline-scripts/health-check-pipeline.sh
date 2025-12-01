#!/bin/bash

# Comprehensive Health Check Script for Data Pipeline
# Checks: Docker services, Kafka Connect, Topics, Schema Registry, Connectors

set +e  # Don't exit on error - we want to check everything

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
SCHEMA_REGISTRY_URL="${SCHEMA_REGISTRY_URL:-http://localhost:8081}"
KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka-1}"
BOOTSTRAP_SERVERS="kafka-1:29092,kafka-2:29092,kafka-3:29092"

# Check if jq is available
if command -v jq &> /dev/null; then
    USE_JQ=true
else
    USE_JQ=false
fi

# Check if docker is available
if command -v docker &> /dev/null; then
    USE_DOCKER=true
else
    USE_DOCKER=false
fi

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Data Pipeline Health Check - $(date +"%Y-%m-%d %H:%M:%S")     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# 1. DOCKER SERVICES STATUS
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}1. DOCKER SERVICES STATUS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$USE_DOCKER" = true ]; then
    services=("fotobook-postgres" "zookeeper" "kafka-1" "kafka-2" "kafka-3" "schema-registry" "kafka-connect" "debezium-ui" "kafka-ui")
    
    for service in "${services[@]}"; do
        status=$(docker ps --filter "name=$service" --format "{{.Status}}" 2>/dev/null)
        if [ -n "$status" ]; then
            health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "N/A")
            if [ "$health" = "healthy" ] || [ "$health" = "N/A" ]; then
                echo -e "  ${GREEN}✓${NC} $service: ${GREEN}RUNNING${NC} ($status)"
            else
                echo -e "  ${YELLOW}⚠${NC} $service: ${YELLOW}$health${NC} ($status)"
            fi
        else
            echo -e "  ${RED}✗${NC} $service: ${RED}NOT RUNNING${NC}"
        fi
    done
else
    echo -e "  ${YELLOW}⚠${NC} Docker not available - skipping service checks"
fi

echo ""

# ============================================================================
# 2. KAFKA CONNECT CONNECTORS
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}2. KAFKA CONNECT CONNECTORS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check Kafka Connect availability
if curl -f -s "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Kafka Connect is accessible at $KAFKA_CONNECT_URL"
    echo ""
    
    # Get connectors list
    connectors_json=$(curl -s "$KAFKA_CONNECT_URL/connectors" 2>/dev/null || echo "[]")
    
    if [ -z "$connectors_json" ] || [ "$connectors_json" = "[]" ]; then
        echo -e "  ${YELLOW}⚠${NC} No connectors found"
    else
        # Parse connectors
        if [ "$USE_JQ" = true ]; then
            connectors=$(echo "$connectors_json" | jq -r '.[]' 2>/dev/null)
        else
            connectors=$(echo "$connectors_json" | sed 's/^\[//' | sed 's/\]$//' | sed 's/"//g' | sed 's/,/\n/g' | sed 's/^ *//' | sed 's/ *$//' | grep -v '^$')
        fi
        
        running_count=0
        failed_count=0
        total_count=0
        
        while IFS= read -r connector || [ -n "$connector" ]; do
            connector=$(echo "$connector" | sed 's/^ *//' | sed 's/ *$//' | tr -d '\n\r' | grep -v '^$')
            if [ -z "$connector" ]; then
                continue
            fi
            
            total_count=$((total_count + 1))
            status_json=$(curl -s "$KAFKA_CONNECT_URL/connectors/$connector/status" 2>/dev/null || echo "")
            
            if [ -z "$status_json" ]; then
                echo -e "  ${YELLOW}⚠${NC} $connector: Could not get status"
                continue
            fi
            
            # Extract status
            if [ "$USE_JQ" = true ]; then
                connector_state=$(echo "$status_json" | jq -r '.connector.state' 2>/dev/null || echo "UNKNOWN")
                tasks=$(echo "$status_json" | jq -r '.tasks[]?.state' 2>/dev/null || echo "")
            else
                connector_state=$(echo "$status_json" | grep -oP '"connector":\{[^}]*"state":"\K[^"]*' | head -1 || echo "UNKNOWN")
            fi
            
            case "$connector_state" in
                "RUNNING")
                    echo -e "  ${GREEN}✓${NC} $connector: ${GREEN}RUNNING${NC}"
                    running_count=$((running_count + 1))
                    
                    # Check tasks
                    if [ "$USE_JQ" = true ] && [ -n "$tasks" ]; then
                        task_failed=false
                        while IFS= read -r task_state; do
                            if [ "$task_state" = "FAILED" ]; then
                                task_failed=true
                                echo -e "      ${RED}✗${NC} Task: ${RED}FAILED${NC}"
                            elif [ "$task_state" = "RUNNING" ]; then
                                echo -e "      ${GREEN}✓${NC} Task: ${GREEN}RUNNING${NC}"
                            else
                                echo -e "      ${YELLOW}⚠${NC} Task: $task_state"
                            fi
                        done <<< "$tasks"
                        if [ "$task_failed" = true ]; then
                            failed_count=$((failed_count + 1))
                        fi
                    fi
                    ;;
                "FAILED")
                    echo -e "  ${RED}✗${NC} $connector: ${RED}FAILED${NC}"
                    failed_count=$((failed_count + 1))
                    
                    # Try to extract error
                    if [ "$USE_JQ" = true ]; then
                        error_msg=$(echo "$status_json" | jq -r '.connector.trace // .tasks[0].trace // ""' 2>/dev/null | head -1 || echo "")
                    else
                        error_msg=$(echo "$status_json" | grep -oP '"trace":"\K[^"]*' | head -1 || echo "")
                    fi
                    if [ -n "$error_msg" ] && [ "$error_msg" != "null" ] && [ "$error_msg" != "" ]; then
                        echo -e "      ${RED}Error:${NC} $(echo "$error_msg" | head -c 150)"
                    fi
                    ;;
                *)
                    echo -e "  ${YELLOW}⚠${NC} $connector: $connector_state"
                    ;;
            esac
        done <<< "$connectors"
        
        echo ""
        echo -e "  ${CYAN}Summary:${NC} $total_count connector(s) - ${GREEN}$running_count running${NC}, ${RED}$failed_count failed${NC}"
    fi
else
    echo -e "  ${RED}✗${NC} Kafka Connect is not accessible at $KAFKA_CONNECT_URL"
fi

echo ""

# ============================================================================
# 3. KAFKA TOPICS
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}3. KAFKA TOPICS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Expected topics from Debezium connectors
debezium_topics=(
    "fotobook.photos"
    "fotobook.albums"
    "fotobook.photo_likeables"
    "fotobook.album_likeables"
    "user_activities"  # From activity-logs-normalized-connector
)

# Recommendation system topics
recommendation_topics=(
    "user_activities"
    "photo_interactions"
    "feed_views"
    "user_profiles_updates"
    "recommendation_dlq"
)

# Combine all topics
all_topics=("${debezium_topics[@]}" "${recommendation_topics[@]}")
# Remove duplicates
all_topics=($(printf '%s\n' "${all_topics[@]}" | sort -u))

if [ "$USE_DOCKER" = true ]; then
    kafka_container=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^kafka-1$" | head -1 || echo "")
    
    if [ -n "$kafka_container" ]; then
        echo -e "  ${GREEN}✓${NC} Using Kafka container: $kafka_container"
        echo ""
        
        # Get all existing topics
        existing_topics=$(docker exec "$kafka_container" kafka-topics \
            --bootstrap-server "$BOOTSTRAP_SERVERS" \
            --list 2>/dev/null | tr '\n' ' ' || echo "")
        
        topics_found=0
        topics_missing=0
        
        for topic in "${all_topics[@]}"; do
            if echo "$existing_topics" | grep -qw "$topic"; then
                # Get topic details
                topic_info=$(docker exec "$kafka_container" kafka-topics \
                    --bootstrap-server "$BOOTSTRAP_SERVERS" \
                    --describe --topic "$topic" 2>/dev/null || echo "")
                
                partition_count=$(echo "$topic_info" | grep -c "Partition:" || echo "0")
                replication=$(echo "$topic_info" | grep -oP "ReplicationFactor:\K[0-9]+" | head -1 || echo "?")
                
                echo -e "  ${GREEN}✓${NC} $topic"
                echo -e "      Partitions: $partition_count, Replication: $replication"
                topics_found=$((topics_found + 1))
            else
                echo -e "  ${YELLOW}⚠${NC} $topic: ${YELLOW}Not created yet${NC}"
                topics_missing=$((topics_missing + 1))
            fi
        done
        
        echo ""
        echo -e "  ${CYAN}Summary:${NC} ${GREEN}$topics_found found${NC}, ${YELLOW}$topics_missing not created${NC}"
        echo -e "  ${CYAN}Note:${NC} Topics may be auto-created when connectors process data"
    else
        echo -e "  ${RED}✗${NC} Kafka container 'kafka-1' not found"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Docker not available - cannot check topics"
fi

echo ""

# ============================================================================
# 4. SCHEMA REGISTRY
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}4. SCHEMA REGISTRY${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check Schema Registry availability
if curl -f -s "$SCHEMA_REGISTRY_URL/subjects" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Schema Registry is accessible at $SCHEMA_REGISTRY_URL"
    echo ""
    
    # Get all subjects
    subjects_json=$(curl -s "$SCHEMA_REGISTRY_URL/subjects" 2>/dev/null || echo "[]")
    
    if [ -z "$subjects_json" ] || [ "$subjects_json" = "[]" ]; then
        echo -e "  ${YELLOW}⚠${NC} No schemas registered"
    else
        # Expected schemas (based on recommendation topics)
        expected_schemas=(
            "user_activities-value"
            "photo_interactions-value"
            "feed_views-value"
            "user_profiles_updates-value"
        )
        
        if [ "$USE_JQ" = true ]; then
            subjects=$(echo "$subjects_json" | jq -r '.[]' 2>/dev/null)
            subject_count=$(echo "$subjects_json" | jq 'length' 2>/dev/null || echo "0")
        else
            subjects=$(echo "$subjects_json" | sed 's/^\[//' | sed 's/\]$//' | sed 's/"//g' | sed 's/,/\n/g' | sed 's/^ *//' | sed 's/ *$//' | grep -v '^$')
            subject_count=$(echo "$subjects" | wc -l | tr -d ' ')
        fi
        
        echo -e "  ${CYAN}Registered Schemas:${NC} $subject_count"
        echo ""
        
        # List all subjects
        if [ -n "$subjects" ]; then
            while IFS= read -r subject || [ -n "$subject" ]; do
                subject=$(echo "$subject" | sed 's/^ *//' | sed 's/ *$//' | tr -d '\n\r' | grep -v '^$')
                if [ -z "$subject" ]; then
                    continue
                fi
                
                # Get schema versions
                versions_json=$(curl -s "$SCHEMA_REGISTRY_URL/subjects/$subject/versions" 2>/dev/null || echo "[]")
                if [ "$USE_JQ" = true ]; then
                    version_count=$(echo "$versions_json" | jq 'length' 2>/dev/null || echo "0")
                else
                    version_count=$(echo "$versions_json" | grep -o '[0-9]' | wc -l | tr -d ' ')
                fi
                
                # Check if expected
                is_expected=false
                for expected in "${expected_schemas[@]}"; do
                    if [ "$subject" = "$expected" ]; then
                        is_expected=true
                        break
                    fi
                done
                
                if [ "$is_expected" = true ]; then
                    echo -e "  ${GREEN}✓${NC} $subject (${GREEN}expected${NC}, $version_count version(s))"
                else
                    echo -e "  ${CYAN}•${NC} $subject ($version_count version(s))"
                fi
            done <<< "$subjects"
        fi
        
        # Check for missing expected schemas
        echo ""
        missing_schemas=0
        for expected in "${expected_schemas[@]}"; do
            if ! echo "$subjects" | grep -q "^$expected$"; then
                echo -e "  ${YELLOW}⚠${NC} $expected: ${YELLOW}Not registered${NC}"
                missing_schemas=$((missing_schemas + 1))
            fi
        done
        
        if [ $missing_schemas -eq 0 ]; then
            echo -e "  ${GREEN}✓${NC} All expected schemas are registered"
        fi
    fi
else
    echo -e "  ${RED}✗${NC} Schema Registry is not accessible at $SCHEMA_REGISTRY_URL"
fi

echo ""

# ============================================================================
# 5. SUMMARY
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}5. SUMMARY${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Count issues
issues=0

# Check services
if [ "$USE_DOCKER" = true ]; then
    for service in "${services[@]}"; do
        if ! docker ps --filter "name=$service" --format "{{.Status}}" 2>/dev/null | grep -q .; then
            issues=$((issues + 1))
        fi
    done
fi

# Check connectors
if curl -f -s "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; then
    connectors_json=$(curl -s "$KAFKA_CONNECT_URL/connectors" 2>/dev/null || echo "[]")
    if [ -n "$connectors_json" ] && [ "$connectors_json" != "[]" ]; then
        # Count failed connectors (simplified check)
        if [ "$USE_JQ" = true ]; then
            connectors=$(echo "$connectors_json" | jq -r '.[]' 2>/dev/null)
        else
            connectors=$(echo "$connectors_json" | sed 's/^\[//' | sed 's/\]$//' | sed 's/"//g' | sed 's/,/\n/g' | sed 's/^ *//' | sed 's/ *$//' | grep -v '^$')
        fi
        
        while IFS= read -r connector || [ -n "$connector" ]; do
            connector=$(echo "$connector" | sed 's/^ *//' | sed 's/ *$//' | tr -d '\n\r' | grep -v '^$')
            if [ -z "$connector" ]; then
                continue
            fi
            
            status_json=$(curl -s "$KAFKA_CONNECT_URL/connectors/$connector/status" 2>/dev/null || echo "")
            if [ -n "$status_json" ]; then
                if [ "$USE_JQ" = true ]; then
                    state=$(echo "$status_json" | jq -r '.connector.state' 2>/dev/null || echo "")
                else
                    state=$(echo "$status_json" | grep -oP '"connector":\{[^}]*"state":"\K[^"]*' | head -1 || echo "")
                fi
                if [ "$state" = "FAILED" ]; then
                    issues=$((issues + 1))
                fi
            fi
        done <<< "$connectors"
    fi
fi

if [ $issues -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${GREEN}All systems operational${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} ${YELLOW}$issues issue(s) detected${NC} - review details above"
fi

# ============================================================================
# WEB UI ACCESS
# ============================================================================
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}WEB UI ACCESS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check Debezium UI
if curl -f -s "http://localhost:8080" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Debezium UI: ${CYAN}http://localhost:8080${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} Debezium UI: ${CYAN}http://localhost:8080${NC} (not accessible)"
fi

# Check Kafka UI
if curl -f -s "http://localhost:8090" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Kafka UI: ${CYAN}http://localhost:8090${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} Kafka UI: ${CYAN}http://localhost:8090${NC} (not accessible)"
fi

# Other services
echo -e "  ${CYAN}ℹ${NC}  Schema Registry: ${CYAN}http://localhost:8081${NC}"
echo -e "  ${CYAN}ℹ${NC}  Kafka Connect: ${CYAN}http://localhost:8083${NC}"
echo -e "  ${CYAN}ℹ${NC}  Grafana: ${CYAN}http://localhost:3000${NC} (admin/admin)"
echo -e "  ${CYAN}ℹ${NC}  Prometheus: ${CYAN}http://localhost:9090${NC}"

echo ""
echo -e "${CYAN}Health check completed at $(date +"%Y-%m-%d %H:%M:%S")${NC}"
echo ""