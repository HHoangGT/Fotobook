package com.fotobook.recommendation.flink.models;

import java.io.Serializable;
import java.util.Map;

/**
 * Photo Like Count aggregation result
 */
public class PhotoLikeCount implements Serializable {
    private Long photoId;
    private Long count;
    private Long windowStart;
    private Long windowEnd;

    public PhotoLikeCount() {}

    public PhotoLikeCount(Long photoId, Long count, Long windowStart, Long windowEnd) {
        this.photoId = photoId;
        this.count = count;
        this.windowStart = windowStart;
        this.windowEnd = windowEnd;
    }

    // Getters and Setters
    public Long getPhotoId() { return photoId; }
    public void setPhotoId(Long photoId) { this.photoId = photoId; }

    public Long getCount() { return count; }
    public void setCount(Long count) { this.count = count; }

    public Long getWindowStart() { return windowStart; }
    public void setWindowStart(Long windowStart) { this.windowStart = windowStart; }

    public Long getWindowEnd() { return windowEnd; }
    public void setWindowEnd(Long windowEnd) { this.windowEnd = windowEnd; }
}