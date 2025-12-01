package com.fotobook.recommendation.flink.models;

import java.io.Serializable;
import java.util.Map;

/**
 * Photo Interaction model matching Avro schema
 */
public class PhotoInteraction implements Serializable {
    private String eventId;
    private Long userId;
    private Long photoId;
    private String interactionType; // LIKE, UNLIKE, VIEW, COMMENT, SHARE
    private Long photoOwnerId;
    private String photoTitle;
    private String photoMode;
    private Map<String, String> metadata;
    private Long timestamp;
    private String op;
    private Long tsMs;

    // Constructors
    public PhotoInteraction() {}

    public PhotoInteraction(String eventId, Long userId, Long photoId, 
                           String interactionType, Long timestamp) {
        this.eventId = eventId;
        this.userId = userId;
        this.photoId = photoId;
        this.interactionType = interactionType;
        this.timestamp = timestamp;
    }

    // Getters and Setters
    public String getEventId() { return eventId; }
    public void setEventId(String eventId) { this.eventId = eventId; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public Long getPhotoId() { return photoId; }
    public void setPhotoId(Long photoId) { this.photoId = photoId; }

    public String getInteractionType() { return interactionType; }
    public void setInteractionType(String interactionType) { this.interactionType = interactionType; }

    public Long getPhotoOwnerId() { return photoOwnerId; }
    public void setPhotoOwnerId(Long photoOwnerId) { this.photoOwnerId = photoOwnerId; }

    public String getPhotoTitle() { return photoTitle; }
    public void setPhotoTitle(String photoTitle) { this.photoTitle = photoTitle; }

    public String getPhotoMode() { return photoMode; }
    public void setPhotoMode(String photoMode) { this.photoMode = photoMode; }

    public Map<String, String> getMetadata() { return metadata; }
    public void setMetadata(Map<String, String> metadata) { this.metadata = metadata; }

    public Long getTimestamp() { return timestamp; }
    public void setTimestamp(Long timestamp) { this.timestamp = timestamp; }

    public String getOp() { return op; }
    public void setOp(String op) { this.op = op; }

    public Long getTsMs() { return tsMs; }
    public void setTsMs(Long tsMs) { this.tsMs = tsMs; }

    @Override
    public String toString() {
        return String.format("PhotoInteraction{userId=%d, photoId=%d, interactionType=%s, timestamp=%d}",
            userId, photoId, interactionType, timestamp);
    }
}