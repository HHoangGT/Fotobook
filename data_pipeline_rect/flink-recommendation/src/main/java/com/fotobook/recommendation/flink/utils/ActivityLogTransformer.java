package com.fotobook.recommendation.flink.utils;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fotobook.recommendation.flink.models.UserActivity;
import org.apache.flink.api.common.functions.RichMapFunction;
import org.apache.flink.configuration.Configuration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Map;

/**
 * Transforms Debezium JSON message to UserActivity POJO
 * 
 * Expected JSON format from Debezium (after unwrap):
 * {
 *   "id": "...",
 *   "user_id": 123,
 *   "activity_type": "LIKE",
 *   "target_type": "photo",
 *   "target_id": 456,
 *   "metadata": {...},
 *   "created_at": "2024-01-01T00:00:00Z",
 *   "op": "c",
 *   "source": {
 *     "ts_ms": 1234567890
 *   }
 * }
 */
public class ActivityLogTransformer extends RichMapFunction<String, UserActivity> {
    private static final Logger LOG = LoggerFactory.getLogger(ActivityLogTransformer.class);
    private transient ObjectMapper objectMapper;

    @Override
    public void open(Configuration parameters) throws Exception {
        super.open(parameters);
        objectMapper = new ObjectMapper();
    }

    @Override
    public UserActivity map(String jsonString) throws Exception {
        try {
            if (jsonString == null || jsonString.trim().isEmpty()) {
                LOG.warn("⚠️ Received null or empty JSON string");
                return null;
            }

            LOG.info("Processing JSON message: {}", jsonString.substring(0, Math.min(200, jsonString.length())));
            JsonNode root = objectMapper.readTree(jsonString);

            // Skip delete operations and tombstones
            // Check for __op field first (Debezium format)
            boolean hasDebeziumOp = root.has("__op");
            if (hasDebeziumOp) {
                String debeziumOp = root.get("__op").asText();
                if ("d".equals(debeziumOp)) {
                    LOG.info("⏭️ Skipping Debezium delete operation (__op=d)");
                    return null;
                }
                // Note: "r" (read/snapshot) and "c" (create) operations are kept
                // If __op exists and is not "d", continue processing (don't check op field)
            } else {
                // Only check "op" field if __op doesn't exist
                String op = root.has("op") ? root.get("op").asText() : null;
                if (op == null || "d".equals(op)) {
                    LOG.info("⏭️ Skipping delete operation or null op (op={})", op);
                    return null;
                }
            }

            UserActivity activity = new UserActivity();

            // Extract fields from JSON
            if (root.has("id")) {
                activity.setEventId(root.get("id").asText());
            }

            if (root.has("user_id")) {
                activity.setUserId(root.get("user_id").asLong());
            }

            // Map "action" field to "activity_type" (Debezium format uses "action")
            if (root.has("activity_type")) {
                activity.setActivityType(root.get("activity_type").asText());
            } else if (root.has("action")) {
                // Convert action to activity_type format
                // like_photo -> LIKE, upload_photo -> UPLOAD, etc.
                String action = root.get("action").asText();
                if ("like_photo".equals(action)) {
                    activity.setActivityType("LIKE");
                } else if ("upload_photo".equals(action)) {
                    activity.setActivityType("UPLOAD");
                } else {
                    // Default: uppercase and remove underscores
                    activity.setActivityType(action.toUpperCase().replace("_", ""));
                }
                LOG.info("Mapped action '{}' to activityType '{}'", action, activity.getActivityType());
            }

            if (root.has("target_type")) {
                activity.setTargetType(root.get("target_type").asText());
            }

            if (root.has("target_id")) {
                activity.setTargetId(root.get("target_id").asLong());
            }

            // Extract metadata
            if (root.has("metadata") && root.get("metadata").isObject()) {
                Map<String, String> metadata = new HashMap<>();
                JsonNode metadataNode = root.get("metadata");
                metadataNode.fields().forEachRemaining(entry -> {
                    metadata.put(entry.getKey(), entry.getValue().asText());
                });
                activity.setMetadata(metadata);
            }

            // Extract timestamp - prefer created_at, fallback to source.ts_ms
            Long timestamp = null;
            if (root.has("created_at")) {
                String createdAt = root.get("created_at").asText();
                // Try to parse ISO 8601 timestamp first
                try {
                    timestamp = java.time.Instant.parse(createdAt).toEpochMilli();
                    LOG.debug("Parsed created_at as ISO 8601: {} -> {}", createdAt, timestamp);
                } catch (Exception e) {
                    // Try to parse as number (could be milliseconds, microseconds, or nanoseconds)
                    try {
                        long tsValue = Long.parseLong(createdAt);
                        // If value is very large (> year 2100 in milliseconds), assume microseconds
                        if (tsValue > 4102444800000L) { // Year 2100 in milliseconds
                            // Likely microseconds or nanoseconds
                            if (tsValue > 4102444800000000L) {
                                // Nanoseconds - convert to milliseconds
                                timestamp = tsValue / 1_000_000;
                                LOG.debug("Parsed created_at as nanoseconds: {} -> {} ms", createdAt, timestamp);
                            } else {
                                // Microseconds - convert to milliseconds
                                timestamp = tsValue / 1_000;
                                LOG.debug("Parsed created_at as microseconds: {} -> {} ms", createdAt, timestamp);
                            }
                        } else {
                            // Assume milliseconds
                            timestamp = tsValue;
                            LOG.debug("Parsed created_at as milliseconds: {} -> {} ms", createdAt, timestamp);
                        }
                    } catch (NumberFormatException nfe) {
                        LOG.warn("Failed to parse created_at timestamp (not ISO 8601 or number): {}", createdAt);
                    }
                }
            }
            
            // Fallback to source.ts_ms if created_at is not available
            if (timestamp == null && root.has("source") && root.get("source").has("ts_ms")) {
                long tsMs = root.get("source").get("ts_ms").asLong();
                // Handle microseconds (if ts_ms is very large)
                if (tsMs > 4102444800000L) {
                    timestamp = tsMs / 1_000; // Convert microseconds to milliseconds
                    LOG.debug("Parsed source.ts_ms as microseconds: {} -> {} ms", tsMs, timestamp);
                } else {
                    timestamp = tsMs;
                    LOG.debug("Using source.ts_ms as milliseconds: {}", timestamp);
                }
            }
            
            // Final fallback to current time
            if (timestamp == null) {
                timestamp = System.currentTimeMillis();
                LOG.warn("⚠️ No timestamp found, using current time: {}", timestamp);
            }
            
            activity.setTimestamp(timestamp);
            LOG.info("⏰ Set activity timestamp: {} (date: {})", timestamp, new java.util.Date(timestamp));

            // Extract Debezium metadata
            if (root.has("op")) {
                activity.setOp(root.get("op").asText());
            }

            if (root.has("source")) {
                JsonNode source = root.get("source");
                if (source.has("ts_ms")) {
                    activity.setTsMs(source.get("ts_ms").asLong());
                }
            }

            LOG.info("Successfully transformed message to UserActivity: userId={}, activityType={}, targetId={}", 
                activity.getUserId(), activity.getActivityType(), activity.getTargetId());
            return activity;

        } catch (Exception e) {
            // Log error but don't throw to prevent job restart
            // Just skip invalid messages
            String jsonPreview = jsonString != null && jsonString.length() > 200 
                ? jsonString.substring(0, 200) + "..." 
                : jsonString;
            LOG.warn("Error transforming JSON to UserActivity (skipping message): {}", jsonPreview, e);
            return null; // Return null to skip invalid messages
        }
    }
}