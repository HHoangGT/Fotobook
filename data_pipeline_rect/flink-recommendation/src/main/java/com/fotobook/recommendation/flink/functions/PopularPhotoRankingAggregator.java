package com.fotobook.recommendation.flink.functions;

import com.fotobook.recommendation.flink.models.UserActivity;
import com.fotobook.recommendation.flink.models.PopularPhoto;
import org.apache.flink.api.common.functions.AggregateFunction;

/**
 * Aggregates activities per photo for popularity ranking
 */
public class PopularPhotoRankingAggregator implements AggregateFunction<
    UserActivity,
    PopularPhotoRankingAggregator.PopularPhotoAccumulator,
    PopularPhoto> {

    @Override
    public PopularPhotoRankingAggregator.PopularPhotoAccumulator createAccumulator() {
        return new PopularPhotoAccumulator();
    }

    @Override
    public PopularPhotoRankingAggregator.PopularPhotoAccumulator add(UserActivity activity, PopularPhotoRankingAggregator.PopularPhotoAccumulator accumulator) {
        if (accumulator.photoId == null) {
            accumulator.photoId = activity.getTargetId();
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
    public PopularPhoto getResult(PopularPhotoRankingAggregator.PopularPhotoAccumulator accumulator) {
        // Calculate popularity score
        double score = accumulator.likeCount * 2.0 +
                      accumulator.viewCount * 0.5 +
                      accumulator.commentCount * 3.0;

        PopularPhoto result = new PopularPhoto();
        result.setPhotoId(accumulator.photoId);
        result.setScore(score);
        result.setLikeCount(accumulator.likeCount);
        result.setViewCount(accumulator.viewCount);
        result.setCommentCount(accumulator.commentCount);
        result.setWindowStart(accumulator.windowStart);
        result.setWindowEnd(accumulator.windowEnd);

        return result;
    }

    @Override
    public PopularPhotoRankingAggregator.PopularPhotoAccumulator merge(PopularPhotoRankingAggregator.PopularPhotoAccumulator a, PopularPhotoRankingAggregator.PopularPhotoAccumulator b) {
        a.likeCount += b.likeCount;
        a.viewCount += b.viewCount;
        a.commentCount += b.commentCount;
        return a;
    }

    public static class PopularPhotoAccumulator {
        public Long photoId;
        public Long likeCount = 0L;
        public Long viewCount = 0L;
        public Long commentCount = 0L;
        public Long windowStart;
        public Long windowEnd;
    }
}