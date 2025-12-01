package com.fotobook.recommendation.flink.functions;

import com.fotobook.recommendation.flink.models.PhotoInteraction;
import com.fotobook.recommendation.flink.models.UserPreferenceVector;
import org.apache.flink.api.common.functions.AggregateFunction;

import java.util.HashMap;
import java.util.Map;

/**
 * Aggregates user photo interactions into preference vectors
 */
public class UserPreferenceVectorAggregator implements AggregateFunction<
    PhotoInteraction,
    UserPreferenceVectorAggregator.UserPreferenceVectorAccumulator,
    UserPreferenceVector> {

    @Override
    public UserPreferenceVectorAggregator.UserPreferenceVectorAccumulator createAccumulator() {
        return new UserPreferenceVectorAccumulator();
    }

    @Override
    public UserPreferenceVectorAggregator.UserPreferenceVectorAccumulator add(PhotoInteraction interaction, 
                                               UserPreferenceVectorAggregator.UserPreferenceVectorAccumulator accumulator) {
        if (accumulator.userId == null) {
            accumulator.userId = interaction.getUserId();
        }

        Long photoId = interaction.getPhotoId();
        String interactionType = interaction.getInteractionType();

        // Calculate preference score based on interaction type
        double score = calculateInteractionScore(interactionType);
        
        // Accumulate preference (weighted average)
        double currentScore = accumulator.preferences.getOrDefault(photoId, 0.0);
        long currentCount = accumulator.interactionCounts.getOrDefault(photoId, 0L);
        
        double newScore = (currentScore * currentCount + score) / (currentCount + 1);
        accumulator.preferences.put(photoId, newScore);
        accumulator.interactionCounts.put(photoId, currentCount + 1);

        return accumulator;
    }

    @Override
    public UserPreferenceVector getResult(UserPreferenceVectorAggregator.UserPreferenceVectorAccumulator accumulator) {
        UserPreferenceVector result = new UserPreferenceVector(accumulator.userId);
        result.setPhotoPreferences(new HashMap<>(accumulator.preferences));
        result.setWindowStart(accumulator.windowStart);
        result.setWindowEnd(accumulator.windowEnd);
        return result;
    }

    @Override
    public UserPreferenceVectorAggregator.UserPreferenceVectorAccumulator merge(UserPreferenceVectorAggregator.UserPreferenceVectorAccumulator a, 
                                                 UserPreferenceVectorAggregator.UserPreferenceVectorAccumulator b) {
        // Merge preferences with weighted average
        for (Map.Entry<Long, Double> entry : b.preferences.entrySet()) {
            Long photoId = entry.getKey();
            double scoreB = entry.getValue();
            long countB = b.interactionCounts.getOrDefault(photoId, 1L);
            
            double scoreA = a.preferences.getOrDefault(photoId, 0.0);
            long countA = a.interactionCounts.getOrDefault(photoId, 0L);
            
            if (countA == 0) {
                a.preferences.put(photoId, scoreB);
                a.interactionCounts.put(photoId, countB);
            } else {
                double mergedScore = (scoreA * countA + scoreB * countB) / (countA + countB);
                a.preferences.put(photoId, mergedScore);
                a.interactionCounts.put(photoId, countA + countB);
            }
        }
        return a;
    }

    private double calculateInteractionScore(String interactionType) {
        switch (interactionType) {
            case "LIKE": return 3.0;
            case "VIEW": return 1.0;
            case "COMMENT": return 5.0;
            case "SHARE": return 4.0;
            default: return 0.5;
        }
    }

    public static class UserPreferenceVectorAccumulator {
        public Long userId;
        public Map<Long, Double> preferences = new HashMap<>();
        public Map<Long, Long> interactionCounts = new HashMap<>();
        public Long windowStart;
        public Long windowEnd;
    }
}