package com.fotobook.recommendation.flink.models;

import java.io.Serializable;
import java.util.HashMap;
import java.util.Map;

/**
 * User Preference Vector
 */
public class UserPreferenceVector implements Serializable {
    private Long userId;
    private Map<Long, Double> photoPreferences; // photoId -> preference score
    private Long windowStart;
    private Long windowEnd;

    public UserPreferenceVector() {
        this.photoPreferences = new HashMap<>();
    }

    public UserPreferenceVector(Long userId) {
        this.userId = userId;
        this.photoPreferences = new HashMap<>();
    }

    // Getters and Setters
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public Map<Long, Double> getPhotoPreferences() { return photoPreferences; }
    public void setPhotoPreferences(Map<Long, Double> photoPreferences) { 
        this.photoPreferences = photoPreferences; 
    }

    public void addPreference(Long photoId, Double score) {
        this.photoPreferences.put(photoId, score);
    }

    public Double getPreference(Long photoId) {
        return photoPreferences.getOrDefault(photoId, 0.0);
    }

    public Long getWindowStart() { return windowStart; }
    public void setWindowStart(Long windowStart) { this.windowStart = windowStart; }

    public Long getWindowEnd() { return windowEnd; }
    public void setWindowEnd(Long windowEnd) { this.windowEnd = windowEnd; }
}