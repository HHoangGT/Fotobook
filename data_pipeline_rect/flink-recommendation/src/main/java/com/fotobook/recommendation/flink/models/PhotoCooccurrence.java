package com.fotobook.recommendation.flink.models;

import java.io.Serializable;

/**
 * Photo Co-occurrence
 */
public class PhotoCooccurrence implements Serializable {
    private Long photo1Id;
    private Long photo2Id;
    private Long cooccurrenceCount;
    private Long windowStart;
    private Long windowEnd;

    public PhotoCooccurrence() {}

    public PhotoCooccurrence(Long photo1Id, Long photo2Id, Long cooccurrenceCount) {
        this.photo1Id = photo1Id;
        this.photo2Id = photo2Id;
        this.cooccurrenceCount = cooccurrenceCount;
    }

    // Getters and Setters
    public Long getPhoto1Id() { return photo1Id; }
    public void setPhoto1Id(Long photo1Id) { this.photo1Id = photo1Id; }

    public Long getPhoto2Id() { return photo2Id; }
    public void setPhoto2Id(Long photo2Id) { this.photo2Id = photo2Id; }

    public Long getCooccurrenceCount() { return cooccurrenceCount; }
    public void setCooccurrenceCount(Long cooccurrenceCount) { 
        this.cooccurrenceCount = cooccurrenceCount; 
    }

    public Long getWindowStart() { return windowStart; }
    public void setWindowStart(Long windowStart) { this.windowStart = windowStart; }

    public Long getWindowEnd() { return windowEnd; }
    public void setWindowEnd(Long windowEnd) { this.windowEnd = windowEnd; }
}