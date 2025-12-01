#!/bin/bash

# Check Debezium Connectors Status and Output
# Usage: ./check-debezium.sh [connector-name]

set -e

KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "  Debezium Connectors Check"
echo "=========================================="
echo ""

# Check Kafka Connect is running
if ! curl -f -s "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; then
    echo -e "${RED}✗ Kafka Connect not accessible at $KAFKA_CONNECT_URL${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Kafka Connect is running${NC}"
echo ""

# List all connectors
echo -e "${CYAN}1. All registered connectors:${NC}"
CONNECTORS=$(curl -s "$KAFKA_CONNECT_URL/connectors" 2>/dev/null)
echo "$CONNECTORS" | jq -r '.[]' 2>/dev/null || echo "$CONNECTORS"
echo ""

# Check specific connector or all
CONNECTOR_NAME="${1:-all}"

# Function to find connector by partial name
find_connector() {
    local search_name="$1"
    local full_list="$2"
    
    # Try exact match first
    if echo "$full_list" | jq -r '.[]' 2>/dev/null | grep -q "^${search_name}$"; then
        echo "$search_name"
        return 0
    fi
    
    # Try with fotobook- prefix
    if echo "$full_list" | jq -r '.[]' 2>/dev/null | grep -q "^fotobook-${search_name}$"; then
        echo "fotobook-${search_name}"
        return 0
    fi
    
    # Try partial match
    local match=$(echo "$full_list" | jq -r ".[] | select(. | contains(\"$search_name\"))" 2>/dev/null | head -1)
    if [ -n "$match" ]; then
        echo "$match"
        return 0
    fi
    
    return 1
}

if [ "$CONNECTOR_NAME" != "all" ]; then
    # Try to find the correct connector name
    ACTUAL_NAME=$(find_connector "$CONNECTOR_NAME" "$CONNECTORS")
    
    if [ -z "$ACTUAL_NAME" ]; then
        echo -e "${RED}✗ Connector '$CONNECTOR_NAME' not found${NC}"
        echo ""
        echo "Available connectors:"
        echo "$CONNECTORS" | jq -r '.[]' 2>/dev/null | sed 's/^/  - /'
        echo ""
        echo "Tip: You can use partial name like 'activity-logs' or full name like 'fotobook-activity-logs-normalized-connector'"
        exit 1
    fi
    
    if [ "$ACTUAL_NAME" != "$CONNECTOR_NAME" ]; then
        echo -e "${YELLOW}⚠ Using connector: $ACTUAL_NAME (matched from '$CONNECTOR_NAME')${NC}"
        echo ""
    fi
    
    # Check specific connector
    echo -e "${CYAN}2. Connector: $ACTUAL_NAME${NC}"
    echo ""
    
    # Get connector status
    STATUS=$(curl -s "$KAFKA_CONNECT_URL/connectors/$ACTUAL_NAME/status" 2>/dev/null)
    echo "Status:"
    
    # Check for errors
    ERROR_CODE=$(echo "$STATUS" | jq -r '.error_code // empty' 2>/dev/null)
    if [ -n "$ERROR_CODE" ] && [ "$ERROR_CODE" != "null" ]; then
        echo -e "${RED}✗ Error: $(echo "$STATUS" | jq -r '.message' 2>/dev/null)${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check connector logs: docker logs kafka-connect -f | grep $ACTUAL_NAME"
        echo "  2. Verify connector is registered: curl $KAFKA_CONNECT_URL/connectors"
        echo "  3. Try restarting connector: curl -X POST $KAFKA_CONNECT_URL/connectors/$ACTUAL_NAME/restart"
    else
        echo "$STATUS" | jq '.' 2>/dev/null || echo "$STATUS"
        
        # Extract state
        STATE=$(echo "$STATUS" | jq -r '.connector.state // empty' 2>/dev/null)
        if [ -n "$STATE" ] && [ "$STATE" != "null" ]; then
            if [ "$STATE" = "RUNNING" ]; then
                echo -e "${GREEN}✓ Connector state: $STATE${NC}"
            else
                echo -e "${RED}✗ Connector state: $STATE${NC}"
            fi
        fi
        
        # Show tasks
        TASKS=$(echo "$STATUS" | jq -r '.tasks[]? | "    Task \(.id): \(.state)"' 2>/dev/null)
        if [ -n "$TASKS" ]; then
            echo ""
            echo "Tasks:"
            echo "$TASKS"
        fi
    fi
    echo ""
    
    # Get connector config
    echo "Configuration:"
    CONFIG=$(curl -s "$KAFKA_CONNECT_URL/connectors/$ACTUAL_NAME/config" 2>/dev/null)
    
    ERROR_CODE=$(echo "$CONFIG" | jq -r '.error_code // empty' 2>/dev/null)
    if [ -n "$ERROR_CODE" ] && [ "$ERROR_CODE" != "null" ]; then
        echo -e "${RED}✗ Error: $(echo "$CONFIG" | jq -r '.message' 2>/dev/null)${NC}"
    else
        echo "$CONFIG" | jq '.' 2>/dev/null || echo "$CONFIG"
    fi
    
else
    # Check all connectors - FIX: Don't use pipe into while, use array instead
    echo -e "${CYAN}2. All Connectors Status:${NC}"
    echo ""
    
    CONNECTOR_LIST=$(curl -s "$KAFKA_CONNECT_URL/connectors" 2>/dev/null)
    
    # Extract connector names into array
    if command -v jq &> /dev/null; then
        # Use jq to extract connector names
        CONNECTOR_ARRAY=($(echo "$CONNECTOR_LIST" | jq -r '.[]' 2>/dev/null || echo ""))
    else
        # Fallback: parse JSON manually
        CONNECTOR_ARRAY=($(echo "$CONNECTOR_LIST" | sed 's/\[//' | sed 's/\]//' | sed 's/"//g' | sed 's/,/ /g' | tr -d '\n'))
    fi
    
    if [ ${#CONNECTOR_ARRAY[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠ No connectors found or could not parse connector list${NC}"
        echo "Raw output: $CONNECTOR_LIST"
    else
        # Loop through array (not pipe)
        for connector in "${CONNECTOR_ARRAY[@]}"; do
            # Skip empty elements
            if [ -z "$connector" ] || [ "$connector" = "null" ]; then
                continue
            fi
            
            # Trim whitespace
            connector=$(echo "$connector" | xargs)
            
            echo -e "${CYAN}Connector: $connector${NC}"
            
            STATUS=$(curl -s "$KAFKA_CONNECT_URL/connectors/$connector/status" 2>/dev/null)
            
            # Check if status call failed
            if [ -z "$STATUS" ]; then
                echo -e "  ${RED}✗ Could not get status${NC}"
                echo ""
                continue
            fi
            
            # Extract state
            STATE=$(echo "$STATUS" | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
            
            if [ "$STATE" = "RUNNING" ]; then
                echo -e "  ${GREEN}✓ State: $STATE${NC}"
            elif [ "$STATE" = "FAILED" ]; then
                echo -e "  ${RED}✗ State: $STATE${NC}"
            elif [ "$STATE" = "UNKNOWN" ]; then
                echo -e "  ${YELLOW}⚠ Could not parse state${NC}"
                echo "  Raw status: $(echo "$STATUS" | head -3)"
            else
                echo -e "  ${YELLOW}⚠ State: $STATE${NC}"
            fi
            
            # Show tasks status
            if command -v jq &> /dev/null; then
                TASKS=$(echo "$STATUS" | jq -r '.tasks[]? | "    Task \(.id): \(.state)"' 2>/dev/null || echo "")
                if [ -n "$TASKS" ]; then
                    echo "$TASKS"
                fi
                
                # Show errors if any
                ERRORS=$(echo "$STATUS" | jq -r '.connector.trace // .tasks[0].trace // empty' 2>/dev/null)
                if [ -n "$ERRORS" ] && [ "$ERRORS" != "null" ] && [ "$ERRORS" != "" ]; then
                    echo -e "  ${RED}Errors:${NC}"
                    echo "$ERRORS" | head -10 | sed 's/^/    /'
                fi
                
                # Show worker ID if available
                WORKER_ID=$(echo "$STATUS" | jq -r '.connector.worker_id // empty' 2>/dev/null)
                if [ -n "$WORKER_ID" ] && [ "$WORKER_ID" != "null" ]; then
                    echo "  Worker ID: $WORKER_ID"
                fi
            else
                # Without jq, show raw status snippet
                echo "  Raw status:"
                echo "$STATUS" | head -10 | sed 's/^/    /'
            fi
            
            echo ""
        done
    fi
fi

echo ""
echo "Done!"
echo ""
echo "Useful commands:"
if [ "$CONNECTOR_NAME" != "all" ] && [ -n "$ACTUAL_NAME" ]; then
    echo "  Check logs: docker logs kafka-connect -f | grep $ACTUAL_NAME"
    echo "  Restart: curl -X POST $KAFKA_CONNECT_URL/connectors/$ACTUAL_NAME/restart"
    echo "  Delete: curl -X DELETE $KAFKA_CONNECT_URL/connectors/$ACTUAL_NAME"
else
    echo "  Check specific connector: ./check-debezium.sh fotobook-activity-logs-normalized-connector"
    echo "  Or use partial name: ./check-debezium.sh activity-logs"
    echo ""
    echo "  To check a specific connector status:"
    echo "    ./check-debezium.sh fotobook-photos-connector"
fi