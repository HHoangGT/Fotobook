package com.fotobook.recommendation.flink.models;

import java.io.Serializable;

/**
 * User Similarity
 */
public class UserSimilarity implements Serializable {
    private Long user1Id;
    private Long user2Id;
    private Double similarity; // cosine similarity score
    private Long windowStart;
    private Long windowEnd;

    public UserSimilarity() {}

    public UserSimilarity(Long user1Id, Long user2Id, Double similarity) {
        this.user1Id = user1Id;
        this.user2Id = user2Id;
        this.similarity = similarity;
    }

    // Getters and Setters
    public Long getUser1Id() { return user1Id; }
    public void setUser1Id(Long user1Id) { this.user1Id = user1Id; }

    public Long getUser2Id() { return user2Id; }
    public void setUser2Id(Long user2Id) { this.user2Id = user2Id; }

    public Double getSimilarity() { return similarity; }
    public void setSimilarity(Double similarity) { this.similarity = similarity; }

    public Long getWindowStart() { return windowStart; }
    public void setWindowStart(Long windowStart) { this.windowStart = windowStart; }

    public Long getWindowEnd() { return windowEnd; }
    public void setWindowEnd(Long windowEnd) { this.windowEnd = windowEnd; }
}