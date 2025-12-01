package com.fotobook.recommendation.flink.functions;

import com.fotobook.recommendation.flink.models.UserActivity;
import com.fotobook.recommendation.flink.models.UserEngagementScore;
import org.apache.flink.api.common.functions.AggregateFunction;

/**
 * Calculates user engagement score based on activities
 * Score = (likes * 2 + views * 1 + comments * 3) / time_weight
 */
public class EngagementScoreCalculator implements AggregateFunction<
    UserActivity,
    EngagementScoreCalculator.EngagementAccumulator,
    UserEngagementScore> {

    @Override
    public EngagementScoreCalculator.EngagementAccumulator createAccumulator() {
        return new EngagementAccumulator();
    }

    @Override
    public EngagementScoreCalculator.EngagementAccumulator add(UserActivity activity, EngagementScoreCalculator.EngagementAccumulator accumulator) {
        if (accumulator.userId == null) {
            accumulator.userId = activity.getUserId();
        }

        String activityType = activity.getActivityType();
        if ("LIKE".equals(activityType)) {
            accumulator.likeCount++;
        } else if ("VIEW".equals(activityType)) {
            accumulator.viewCount++;
        } else if ("COMMENT".equals(activityType)) {
            accumulator.commentCount++;
        }

        return accumulator;
    }

    @Override
    public UserEngagementScore getResult(EngagementScoreCalculator.EngagementAccumulator accumulator) {
        // Calculate engagement score: weighted sum
        double score = accumulator.likeCount * 2.0 +
                      accumulator.viewCount * 1.0 +
                      accumulator.commentCount * 3.0;

        UserEngagementScore result = new UserEngagementScore();
        result.setUserId(accumulator.userId);
        result.setScore(score);
        result.setLikeCount(accumulator.likeCount);
        result.setViewCount(accumulator.viewCount);
        result.setCommentCount(accumulator.commentCount);
        result.setWindowStart(accumulator.windowStart);
        result.setWindowEnd(accumulator.windowEnd);

        return result;
    }

    @Override
    public EngagementScoreCalculator.EngagementAccumulator merge(EngagementScoreCalculator.EngagementAccumulator a, EngagementScoreCalculator.EngagementAccumulator b) {
        a.likeCount += b.likeCount;
        a.viewCount += b.viewCount;
        a.commentCount += b.commentCount;
        return a;
    }

    public static class EngagementAccumulator {
        public Long userId;
        public Long likeCount = 0L;
        public Long viewCount = 0L;
        public Long commentCount = 0L;
        public Long windowStart;
        public Long windowEnd;
    }
}