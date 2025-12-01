package com.fotobook.recommendation.flink.functions;

import com.fotobook.recommendation.flink.models.UserPreferenceVector;
import com.fotobook.recommendation.flink.models.UserSimilarity;
import org.apache.flink.streaming.api.functions.windowing.ProcessAllWindowFunction;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;

import java.util.*;

/**
 * Calculates cosine similarity between all user pairs
 */
public class UserSimilarityCalculator extends ProcessAllWindowFunction<
    UserPreferenceVector,
    UserSimilarity,
    TimeWindow> {

    @Override
    public void process(Context context, 
                       Iterable<UserPreferenceVector> elements,
                       Collector<UserSimilarity> out) throws Exception {
        
        List<UserPreferenceVector> vectors = new ArrayList<>();
        for (UserPreferenceVector vector : elements) {
            vectors.add(vector);
        }

        // Calculate pairwise cosine similarity
        for (int i = 0; i < vectors.size(); i++) {
            for (int j = i + 1; j < vectors.size(); j++) {
                UserPreferenceVector v1 = vectors.get(i);
                UserPreferenceVector v2 = vectors.get(j);

                double similarity = calculateCosineSimilarity(
                    v1.getPhotoPreferences(),
                    v2.getPhotoPreferences()
                );

                UserSimilarity result = new UserSimilarity();
                result.setUser1Id(v1.getUserId());
                result.setUser2Id(v2.getUserId());
                result.setSimilarity(similarity);
                result.setWindowStart(context.window().getStart());
                result.setWindowEnd(context.window().getEnd());

                out.collect(result);
            }
        }
    }

    /**
     * Calculate cosine similarity between two preference vectors
     */
    private double calculateCosineSimilarity(Map<Long, Double> v1, Map<Long, Double> v2) {
        Set<Long> commonPhotos = new HashSet<>(v1.keySet());
        commonPhotos.retainAll(v2.keySet());

        if (commonPhotos.isEmpty()) {
            return 0.0;
        }

        double dotProduct = 0.0;
        double norm1 = 0.0;
        double norm2 = 0.0;

        // Calculate dot product and norms for common photos
        for (Long photoId : commonPhotos) {
            double val1 = v1.getOrDefault(photoId, 0.0);
            double val2 = v2.getOrDefault(photoId, 0.0);
            dotProduct += val1 * val2;
            norm1 += val1 * val1;
            norm2 += val2 * val2;
        }

        // Add contributions from non-common photos to norms
        for (Long photoId : v1.keySet()) {
            if (!commonPhotos.contains(photoId)) {
                double val = v1.get(photoId);
                norm1 += val * val;
            }
        }

        for (Long photoId : v2.keySet()) {
            if (!commonPhotos.contains(photoId)) {
                double val = v2.get(photoId);
                norm2 += val * val;
            }
        }

        double denominator = Math.sqrt(norm1) * Math.sqrt(norm2);
        if (denominator == 0.0) {
            return 0.0;
        }

        return dotProduct / denominator;
    }
}

