package com.fotobook.recommendation.flink.models;

import java.io.Serializable;

/**
 * Popular Photo ranking
 */
public class PopularPhoto implements Serializable {
    private Long photoId;
    private Long rank;
    private Double score;
    private Long likeCount;
    private Long viewCount;
    private Long commentCount;
    private Long windowStart;
    private Long windowEnd;

    public PopularPhoto() {}

    public PopularPhoto(Long photoId, Long rank, Double score, 
                       Long likeCount, Long viewCount, Long commentCount) {
        this.photoId = photoId;
        this.rank = rank;
        this.score = score;
        this.likeCount = likeCount;
        this.viewCount = viewCount;
        this.commentCount = commentCount;
    }

    // Getters and Setters
    public Long getPhotoId() { return photoId; }
    public void setPhotoId(Long photoId) { this.photoId = photoId; }

    public Long getRank() { return rank; }
    public void setRank(Long rank) { this.rank = rank; }

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