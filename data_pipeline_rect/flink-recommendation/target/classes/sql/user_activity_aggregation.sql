-- ============================================================================
-- User Activity Aggregation - Flink SQL Queries
-- ============================================================================
-- This file contains SQL queries for real-time user activity aggregations
-- Using Flink SQL with Kafka source and window functions

-- ============================================================================
-- 1. CREATE KAFKA SOURCE TABLE - User Activities
-- ============================================================================

CREATE TABLE user_activities_source (
    event_id STRING,
    user_id BIGINT,
    activity_type STRING,
    target_type STRING,
    target_id BIGINT,
    metadata MAP<STRING, STRING>,
    `timestamp` BIGINT,
    source STRING,
    _op STRING,
    _ts_ms BIGINT,
    proctime AS PROCTIME(),
    event_time AS TO_TIMESTAMP(FROM_UNIXTIME(`timestamp` / 1000)),
    WATERMARK FOR event_time AS event_time - INTERVAL '10' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'user_activities',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'properties.group.id' = 'flink-sql-user-activities',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081',
    'avro.schema-registry.subject' = 'user_activities-value'
);

-- ============================================================================
-- 2. Photo Like Count - Sliding Window 1 Hour
-- ============================================================================

CREATE TABLE photo_like_count_1h (
    photo_id BIGINT,
    like_count BIGINT,
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (photo_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'photo-like-count-1h',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO photo_like_count_1h
SELECT
    target_id AS photo_id,
    COUNT(*) AS like_count,
    HOP_START(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR) AS window_start,
    HOP_END(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR) AS window_end
FROM user_activities_source
WHERE activity_type = 'LIKE' 
  AND target_type = 'photo'
  AND _op != 'd'  -- Exclude deletes
GROUP BY
    target_id,
    HOP(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR);

-- ============================================================================
-- 3. Photo Like Count - Sliding Window 24 Hours
-- ============================================================================

CREATE TABLE photo_like_count_24h (
    photo_id BIGINT,
    like_count BIGINT,
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (photo_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'photo-like-count-24h',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO photo_like_count_24h
SELECT
    target_id AS photo_id,
    COUNT(*) AS like_count,
    HOP_START(event_time, INTERVAL '1' HOUR, INTERVAL '24' HOUR) AS window_start,
    HOP_END(event_time, INTERVAL '1' HOUR, INTERVAL '24' HOUR) AS window_end
FROM user_activities_source
WHERE activity_type = 'LIKE' 
  AND target_type = 'photo'
  AND _op != 'd'
GROUP BY
    target_id,
    HOP(event_time, INTERVAL '1' HOUR, INTERVAL '24' HOUR);

-- ============================================================================
-- 4. User Engagement Score - Tumbling Window 1 Hour
-- ============================================================================

CREATE TABLE user_engagement_score (
    user_id BIGINT,
    engagement_score DOUBLE,
    like_count BIGINT,
    view_count BIGINT,
    comment_count BIGINT,
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (user_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'user-engagement-score',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO user_engagement_score
SELECT
    user_id,
    -- Engagement score: weighted sum
    SUM(CASE 
        WHEN activity_type = 'LIKE' THEN 2.0
        WHEN activity_type = 'VIEW' THEN 1.0
        WHEN activity_type = 'COMMENT' THEN 3.0
        WHEN activity_type = 'SHARE' THEN 4.0
        ELSE 0.0
    END) AS engagement_score,
    SUM(CASE WHEN activity_type = 'LIKE' THEN 1 ELSE 0 END) AS like_count,
    SUM(CASE WHEN activity_type = 'VIEW' THEN 1 ELSE 0 END) AS view_count,
    SUM(CASE WHEN activity_type = 'COMMENT' THEN 1 ELSE 0 END) AS comment_count,
    TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
    TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end
FROM user_activities_source
WHERE _op != 'd'
GROUP BY
    user_id,
    TUMBLE(event_time, INTERVAL '1' HOUR);

-- ============================================================================
-- 5. Popular Photos Ranking - Tumbling Window 1 Hour
-- ============================================================================

CREATE TABLE popular_photos_ranking (
    photo_id BIGINT,
    rank_position BIGINT,
    popularity_score DOUBLE,
    like_count BIGINT,
    view_count BIGINT,
    comment_count BIGINT,
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (photo_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'popular-photos-ranking',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO popular_photos_ranking
SELECT
    photo_scores.photo_id,
    ROW_NUMBER() OVER (
        PARTITION BY photo_scores.window_start 
        ORDER BY photo_scores.popularity_score DESC
    ) AS rank_position,
    photo_scores.popularity_score,
    photo_scores.like_count,
    photo_scores.view_count,
    photo_scores.comment_count,
    photo_scores.window_start,
    photo_scores.window_end
FROM (
    SELECT
        target_id AS photo_id,
        SUM(CASE 
            WHEN activity_type = 'LIKE' THEN 2.0
            WHEN activity_type = 'VIEW' THEN 0.5
            WHEN activity_type = 'COMMENT' THEN 3.0
            ELSE 0.0
        END) AS popularity_score,
        SUM(CASE WHEN activity_type = 'LIKE' THEN 1 ELSE 0 END) AS like_count,
        SUM(CASE WHEN activity_type = 'VIEW' THEN 1 ELSE 0 END) AS view_count,
        SUM(CASE WHEN activity_type = 'COMMENT' THEN 1 ELSE 0 END) AS comment_count,
        TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
        TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end
    FROM user_activities_source
    WHERE target_type = 'photo' 
      AND _op != 'd'
    GROUP BY
        target_id,
        TUMBLE(event_time, INTERVAL '1' HOUR)
) AS photo_scores;