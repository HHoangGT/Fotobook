-- ============================================================================
-- User-Photo Interaction Matrix - Flink SQL Queries
-- ============================================================================
-- This file contains SQL queries for user-photo interactions,
-- similarity matrix, and co-occurrence calculations

-- ============================================================================
-- 1. CREATE KAFKA SOURCE TABLE - Photo Interactions
-- ============================================================================

CREATE TABLE photo_interactions_source (
    event_id STRING,
    user_id BIGINT,
    photo_id BIGINT,
    interaction_type STRING,
    photo_owner_id BIGINT,
    photo_title STRING,
    photo_mode STRING,
    metadata MAP<STRING, STRING>,
    `timestamp` BIGINT,
    _op STRING,
    _ts_ms BIGINT,
    proctime AS PROCTIME(),
    event_time AS TO_TIMESTAMP(FROM_UNIXTIME(`timestamp` / 1000)),
    WATERMARK FOR event_time AS event_time - INTERVAL '10' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'photo_interactions',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'properties.group.id' = 'flink-sql-photo-interactions',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'avro',
    'avro.schema-registry.url' = 'http://schema-registry:8081',
    'avro.schema-registry.subject' = 'photo_interactions-value'
);

-- ============================================================================
-- 2. Reference Data - Photos (from another Kafka topic or JDBC)
-- ============================================================================

CREATE TABLE photos_reference (
    photo_id BIGINT,
    user_id BIGINT,
    title STRING,
    mode STRING,
    created_at TIMESTAMP(3),
    PRIMARY KEY (photo_id) NOT ENFORCED
) WITH (
    'connector' = 'kafka',
    'topic' = 'fotobook.photos',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'properties.group.id' = 'flink-sql-photos-ref',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json'
);

-- ============================================================================
-- 3. User Preference Vectors - Tumbling Window 1 Hour
-- ============================================================================

CREATE TABLE user_preference_vectors (
    user_id BIGINT,
    photo_id BIGINT,
    preference_score DOUBLE,
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (user_id, photo_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'user-preference-vectors',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO user_preference_vectors
SELECT
    user_id,
    photo_id,
    -- Weighted average preference score
    AVG(CASE 
        WHEN interaction_type = 'LIKE' THEN 3.0
        WHEN interaction_type = 'VIEW' THEN 1.0
        WHEN interaction_type = 'COMMENT' THEN 5.0
        WHEN interaction_type = 'SHARE' THEN 4.0
        ELSE 0.5
    END) AS preference_score,
    TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
    TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end
FROM photo_interactions_source
WHERE interaction_type != 'UNLIKE' 
  AND _op != 'd'
GROUP BY
    user_id,
    photo_id,
    TUMBLE(event_time, INTERVAL '1' HOUR);

-- ============================================================================
-- 4. Photo Co-occurrence Matrix - Tumbling Window 6 Hours
-- ============================================================================
-- Photos that appear together in same user's interactions

CREATE TABLE photo_cooccurrence_matrix (
    photo1_id BIGINT,
    photo2_id BIGINT,
    cooccurrence_count BIGINT,
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (photo1_id, photo2_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'photo-cooccurrence-matrix',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

-- Calculate co-occurrence using self-join
INSERT INTO photo_cooccurrence_matrix
SELECT
    LEAST(p1.photo_id, p2.photo_id) AS photo1_id,
    GREATEST(p1.photo_id, p2.photo_id) AS photo2_id,
    COUNT(*) AS cooccurrence_count,
    TUMBLE_START(p1.event_time, INTERVAL '6' HOUR) AS window_start,
    TUMBLE_END(p1.event_time, INTERVAL '6' HOUR) AS window_end
FROM photo_interactions_source AS p1
INNER JOIN photo_interactions_source AS p2
    ON p1.user_id = p2.user_id
    AND p1.photo_id < p2.photo_id
    AND ABS(UNIX_TIMESTAMP(p1.event_time) - UNIX_TIMESTAMP(p2.event_time)) < 3600  -- Within 1 hour
WHERE p1._op != 'd' AND p2._op != 'd'
GROUP BY
    LEAST(p1.photo_id, p2.photo_id),
    GREATEST(p1.photo_id, p2.photo_id),
    TUMBLE(p1.event_time, INTERVAL '6' HOUR);

-- ============================================================================
-- 5. User-Photo Interaction Score - Real-time
-- ============================================================================

CREATE TABLE user_photo_interaction_scores (
    user_id BIGINT,
    photo_id BIGINT,
    interaction_score DOUBLE,
    last_interaction TIMESTAMP(3),
    PRIMARY KEY (user_id, photo_id) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'user-photo-interaction-scores',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO user_photo_interaction_scores
SELECT
    user_id,
    photo_id,
    SUM(CASE 
        WHEN interaction_type = 'LIKE' THEN 3.0
        WHEN interaction_type = 'VIEW' THEN 1.0
        WHEN interaction_type = 'COMMENT' THEN 5.0
        WHEN interaction_type = 'SHARE' THEN 4.0
        WHEN interaction_type = 'UNLIKE' THEN -2.0
        ELSE 0.0
    END) AS interaction_score,
    MAX(event_time) AS last_interaction
FROM photo_interactions_source
WHERE _op != 'd'
GROUP BY user_id, photo_id;