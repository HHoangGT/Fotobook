package com.fotobook.recommendation.flink.functions;

import com.fotobook.recommendation.flink.models.UserActivity;
import com.fotobook.recommendation.flink.models.PhotoLikeCount;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.streaming.api.windowing.assigners.WindowAssigner;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;

/**
 * Aggregates like count per photo in sliding window
 */
public class PhotoLikeCountAggregator implements AggregateFunction<
    UserActivity, 
    PhotoLikeCountAggregator.PhotoLikeCountAccumulator, 
    PhotoLikeCount> {

    @Override
    public PhotoLikeCountAggregator.PhotoLikeCountAccumulator createAccumulator() {
        return new PhotoLikeCountAccumulator();
    }

    @Override
    public PhotoLikeCountAggregator.PhotoLikeCountAccumulator add(UserActivity activity, PhotoLikeCountAggregator.PhotoLikeCountAccumulator accumulator) {
        if (accumulator.photoId == null) {
            accumulator.photoId = activity.getTargetId();
        }
        accumulator.count++;
        return accumulator;
    }

    @Override
    public PhotoLikeCount getResult(PhotoLikeCountAggregator.PhotoLikeCountAccumulator accumulator) {
        return new PhotoLikeCount(
            accumulator.photoId,
            accumulator.count,
            accumulator.windowStart,
            accumulator.windowEnd
        );
    }

    @Override
    public PhotoLikeCountAggregator.PhotoLikeCountAccumulator merge(PhotoLikeCountAggregator.PhotoLikeCountAccumulator a, PhotoLikeCountAggregator.PhotoLikeCountAccumulator b) {
        a.count += b.count;
        return a;
    }

    // Accumulator class
    public static class PhotoLikeCountAccumulator {
        public Long photoId;
        public Long count = 0L;
        public Long windowStart;
        public Long windowEnd;
    }
}