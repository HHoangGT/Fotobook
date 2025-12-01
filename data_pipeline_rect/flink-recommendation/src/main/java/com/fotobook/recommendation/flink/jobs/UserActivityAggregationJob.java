package com.fotobook.recommendation.flink.jobs;

import com.fotobook.recommendation.flink.models.UserActivity;
import com.fotobook.recommendation.flink.models.PhotoLikeCount;
import com.fotobook.recommendation.flink.models.UserEngagementScore;
import com.fotobook.recommendation.flink.models.PopularPhoto;
import com.fotobook.recommendation.flink.functions.*;
import com.fotobook.recommendation.flink.sinks.RedisFeatureSink;
import com.fotobook.recommendation.flink.sinks.FeatureStoreSink;
import com.fotobook.recommendation.flink.utils.AvroSchemaRegistryDeserializer;
import com.fotobook.recommendation.flink.utils.JsonDeserializer;
import com.fotobook.recommendation.flink.utils.ActivityLogTransformer;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.SlidingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.OutputTag;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;

/**
 * User Activity Aggregation Job
 * 
 * Processes user_activities topic and calculates:
 * - Like count per photo/album (sliding window 1h, 24h)
 * - User engagement score (likes, views, comments)
 * - Popular photos ranking (tumbling window 1h)
 */
public class UserActivityAggregationJob {
    private static final Logger LOG = LoggerFactory.getLogger(UserActivityAggregationJob.class);

    // Configuration
    private static final String KAFKA_BOOTSTRAP_SERVERS = "kafka-1:29092,kafka-2:29092,kafka-3:29092";
    private static final String SCHEMA_REGISTRY_URL = "http://schema-registry:8081";
    private static final String USER_ACTIVITIES_TOPIC = "user_activities";
    private static final String REDIS_HOST = "redis";
    private static final int REDIS_PORT = 6379;

    // Output tags for side outputs
    public static final OutputTag<UserActivity> LATE_DATA_TAG = 
        new OutputTag<UserActivity>("late-data"){};

    public void buildPipeline(StreamExecutionEnvironment env) {
        // 1. Read from Kafka as JSON string (raw from Debezium)
        // Using latest() offset to skip old messages and only process new ones
        KafkaSource<String> kafkaSource = KafkaSource.<String>builder()
            .setBootstrapServers(KAFKA_BOOTSTRAP_SERVERS)
            .setTopics(USER_ACTIVITIES_TOPIC)
            .setGroupId("flink-user-activity-aggregation")
            .setStartingOffsets(OffsetsInitializer.latest())  // Only process new messages, skip old ones
            .setValueOnlyDeserializer(new SimpleStringSchema())  // Read as JSON string
            .build();

        // 2. Transform raw JSON to UserActivity POJO
        DataStream<UserActivity> activityStream = env
            .fromSource(kafkaSource, 
                WatermarkStrategy.noWatermarks(),  // Will add watermark after transformation
                "user-activities-source")
            .name("User Activities Source (JSON)")
            .map(new ActivityLogTransformer())
            .filter(activity -> activity != null)  // Filter out failed transformations
            .name("Transform JSON to UserActivity")
            .assignTimestampsAndWatermarks(
                WatermarkStrategy
                    .<UserActivity>forBoundedOutOfOrderness(Duration.ofSeconds(5))  // Reduced from 10s to 5s for faster window closing
                    .withTimestampAssigner((event, timestamp) -> {
                        long ts = event.getTimestamp();
                        long now = System.currentTimeMillis();
                        long diff = now - ts;
                        // If timestamp is too old (more than 1 hour), use current time to ensure watermark progresses
                        if (diff > 3600000) {  // 1 hour
                            LOG.warn("⚠️ Timestamp is too old ({}ms ago), using current time for watermark", diff);
                            ts = now;
                        }
                        LOG.info("⏰ Assigning timestamp: {} (date: {}), current: {}, diff: {}ms", 
                            ts, new java.util.Date(ts), new java.util.Date(now), diff);
                        return ts;
                    })
                    .withIdleness(Duration.ofSeconds(2))  // Emit watermark even if no events for 2 seconds (reduced for faster processing)
            )
            .name("User Activities Stream");

        // 3. Filter valid activities (exclude deletes, etc.)
        DataStream<UserActivity> validActivities = activityStream
            .filter(activity -> {
                try {
                    if (activity == null) {
                        LOG.debug("Received null activity, skipping");
                        return false;
                    }
                    boolean isValid = activity.getActivityType() != null && 
                                   !"DELETE".equals(activity.getActivityType());
                    if (isValid) {
                        LOG.info("✅ Valid activity: userId={}, type={}, targetId={}, targetType={}", 
                            activity.getUserId(), activity.getActivityType(), activity.getTargetId(), activity.getTargetType());
                    } else {
                        LOG.warn("❌ Invalid activity skipped: userId={}, type={}, targetId={}", 
                            activity != null ? activity.getUserId() : "null", 
                            activity != null ? activity.getActivityType() : "null",
                            activity != null ? activity.getTargetId() : "null");
                    }
                    return isValid;
                } catch (Exception e) {
                    LOG.warn("Error filtering activity (skipping): {}", activity, e);
                    return false; // Skip on error
                }
            })
            .name("Filter Valid Activities");

        // 4. Calculate Like Count per Photo (Sliding Window 1h)
        DataStream<PhotoLikeCount> photoLikeCount1h = validActivities
            .filter(activity -> {
                boolean isLike = "LIKE".equals(activity.getActivityType());
                boolean isPhoto = activity.getTargetType() != null && 
                                 "photo".equalsIgnoreCase(activity.getTargetType());
                if (isLike && isPhoto) {
                    LOG.info("📸 Processing photo like: photoId={}, userId={}", 
                        activity.getTargetId(), activity.getUserId());
                }
                return isLike && isPhoto;
            })
            .keyBy(activity -> activity.getTargetId())
            .window(SlidingEventTimeWindows.of(Time.minutes(1), Time.seconds(10)))
            .aggregate(
                new PhotoLikeCountAggregator(),
                new ProcessWindowFunction<PhotoLikeCount, PhotoLikeCount, Long, TimeWindow>() {
                    @Override
                    public void process(Long key, Context context, Iterable<PhotoLikeCount> elements, Collector<PhotoLikeCount> out) throws Exception {
                        for (PhotoLikeCount plc : elements) {
                            plc.setWindowStart(context.window().getStart());
                            plc.setWindowEnd(context.window().getEnd());
                            LOG.info("📊 Window result: photoId={}, count={}, window=[{} - {}]", 
                                plc.getPhotoId(), plc.getCount(), 
                                new java.util.Date(context.window().getStart()),
                                new java.util.Date(context.window().getEnd()));
                            out.collect(plc);
                        }
                    }
                })
            .name("Photo Like Count 1h");

        // 5. Calculate Like Count per Photo (Sliding Window 24h)
        DataStream<PhotoLikeCount> photoLikeCount24h = validActivities
            .filter(activity -> {
                boolean isLike = "LIKE".equals(activity.getActivityType());
                boolean isPhoto = activity.getTargetType() != null && 
                                 "photo".equalsIgnoreCase(activity.getTargetType());
                return isLike && isPhoto;
            })
            .keyBy(activity -> activity.getTargetId())
            .window(SlidingEventTimeWindows.of(Time.minutes(1), Time.seconds(10)))
            .aggregate(
                new PhotoLikeCountAggregator(),
                new ProcessWindowFunction<PhotoLikeCount, PhotoLikeCount, Long, TimeWindow>() {
                    @Override
                    public void process(Long key, Context context, Iterable<PhotoLikeCount> elements, Collector<PhotoLikeCount> out) throws Exception {
                        for (PhotoLikeCount plc : elements) {
                            plc.setWindowStart(context.window().getStart());
                            plc.setWindowEnd(context.window().getEnd());
                            out.collect(plc);
                        }
                    }
                })
            .name("Photo Like Count 24h");

        // 6. Calculate User Engagement Score
        DataStream<UserEngagementScore> userEngagement = validActivities
            .keyBy(activity -> activity.getUserId())
            .window(TumblingEventTimeWindows.of(Time.hours(1)))
            .aggregate(
                new EngagementScoreCalculator(),
                new ProcessWindowFunction<UserEngagementScore, UserEngagementScore, Long, TimeWindow>() {
                    @Override
                    public void process(Long key, Context context, Iterable<UserEngagementScore> elements, Collector<UserEngagementScore> out) throws Exception {
                        for (UserEngagementScore ues : elements) {
                            ues.setWindowStart(context.window().getStart());
                            ues.setWindowEnd(context.window().getEnd());
                            LOG.info("👤 User Engagement result: userId={}, score={}, window=[{} - {}]", 
                                ues.getUserId(), ues.getScore(),
                                new java.util.Date(context.window().getStart()),
                                new java.util.Date(context.window().getEnd()));
                            out.collect(ues);
                        }
                    }
                })
            .name("User Engagement Score");

        // 7. Popular Photos Ranking (Tumbling Window 1 minute for testing)
        DataStream<PopularPhoto> popularPhotos = validActivities
            .filter(activity -> activity.getTargetType() != null && 
                               "photo".equalsIgnoreCase(activity.getTargetType()))
            .keyBy(activity -> activity.getTargetId())
            .window(TumblingEventTimeWindows.of(Time.minutes(1)))
            .aggregate(
                new PopularPhotoRankingAggregator(),
                new ProcessWindowFunction<PopularPhoto, PopularPhoto, Long, TimeWindow>() {
                    @Override
                    public void process(Long key, Context context, Iterable<PopularPhoto> elements, Collector<PopularPhoto> out) throws Exception {
                        for (PopularPhoto pp : elements) {
                            pp.setWindowStart(context.window().getStart());
                            pp.setWindowEnd(context.window().getEnd());
                            LOG.info("📸 Popular Photo result: photoId={}, score={}, window=[{} - {}]", 
                                pp.getPhotoId(), pp.getScore(),
                                new java.util.Date(context.window().getStart()),
                                new java.util.Date(context.window().getEnd()));
                            out.collect(pp);
                        }
                    }
                })
            .windowAll(TumblingEventTimeWindows.of(Time.minutes(1)))
            .process(new PopularPhotoRankingProcess())
            .name("Popular Photos Ranking");

        // 8. Sink to Redis
        photoLikeCount1h.addSink(new RedisFeatureSink<>(
            REDIS_HOST, 
            REDIS_PORT,
            "photo:like_count:1h"
        )).name("Redis Sink - Photo Like Count 1h");

        photoLikeCount24h.addSink(new RedisFeatureSink<>(
            REDIS_HOST, 
            REDIS_PORT,
            "photo:like_count:24h"
        )).name("Redis Sink - Photo Like Count 24h");

        userEngagement.addSink(new RedisFeatureSink<>(
            REDIS_HOST, 
            REDIS_PORT,
            "user:engagement_score"
        )).name("Redis Sink - User Engagement");

        // 9. Sink popular photos to Feature Store
        popularPhotos.addSink(new FeatureStoreSink<>(
            "feature_store",
            "popular_photos"
        )).name("Feature Store Sink - Popular Photos");
    }
}