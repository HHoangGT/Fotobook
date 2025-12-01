package com.fotobook.recommendation.flink.models;

import java.io.Serializable;

/**
 * User Engagement Score
 */
public class UserEngagementScore implements Serializable {
    private Long userId;
    private Double score;
    private Long likeCount;
    private Long viewCount;
    private Long commentCount;
    private Long windowStart;
    private Long windowEnd;

    public UserEngagementScore() {}

    // Getters and Setters
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public Double getScore() { return score; }
    public void setScore(Double score) { this.score = score; }

    public Long getLikeCount() { return likeCount; }
    public void setLikeCount(Long likeCount) { this.likeCount = likeCount; }

    public Long getViewCount() { return viewCount; }
    public void setViewCount(Long viewCount) { this.viewCount = viewCount; }

    public Long getCommentCount() { return commentCount; }
    public void setCommentCount(Long commentCount) { this.commentCount = commentCount; }

    public Long getWindowStart() { return windowStart; }
    public void setWindowStart(Long windowStart) { this.windowStart = windowStart; }

    public Long getWindowEnd() { return windowEnd; }
    public void setWindowEnd(Long windowEnd) { this.windowEnd = windowEnd; }
}

