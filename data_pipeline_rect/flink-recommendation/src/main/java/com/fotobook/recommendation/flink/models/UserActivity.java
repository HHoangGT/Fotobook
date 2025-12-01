package com.fotobook.recommendation.flink.models;

import java.io.Serializable;
import java.util.Map;

/**
 * User Activity model matching Avro schema
 */
public class UserActivity implements Serializable {
    private String eventId;
    private Long userId;
    private String activityType; // VIEW, LIKE, COMMENT, etc.
    private String targetType;   // photo, album, user
    private Long targetId;
    private Map<String, String> metadata;
    private Long timestamp;
    private String source;
    private String op;           // Debezium operation
    private Long tsMs;           // Debezium timestamp

    // Constructors
    public UserActivity() {}

    public UserActivity(String eventId, Long userId, String activityType, 
                       String targetType, Long targetId, Long timestamp) {
        this.eventId = eventId;
        this.userId = userId;
        this.activityType = activityType;
        this.targetType = targetType;
        this.targetId = targetId;
        this.timestamp = timestamp;
    }

    // Getters and Setters
    public String getEventId() { return eventId; }
    public void setEventId(String eventId) { this.eventId = eventId; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public String getActivityType() { return activityType; }
    public void setActivityType(String activityType) { this.activityType = activityType; }

    public String getTargetType() { return targetType; }
    public void setTargetType(String targetType) { this.targetType = targetType; }

    public Long getTargetId() { return targetId; }
    public void setTargetId(Long targetId) { this.targetId = targetId; }

    public Map<String, String> getMetadata() { return metadata; }
    public void setMetadata(Map<String, String> metadata) { this.metadata = metadata; }

    public Long getTimestamp() { return timestamp; }
    public void setTimestamp(Long timestamp) { this.timestamp = timestamp; }

    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }

    public String getOp() { return op; }
    public void setOp(String op) { this.op = op; }

    public Long getTsMs() { return tsMs; }
    public void setTsMs(Long tsMs) { this.tsMs = tsMs; }

    @Override
    public String toString() {
        return String.format("UserActivity{userId=%d, activityType=%s, targetType=%s, targetId=%d, timestamp=%d}",
            userId, activityType, targetType, targetId, timestamp);
    }
}