-- ============================================================================
-- Reference Data Joins - Flink SQL Queries
-- ============================================================================
-- This file contains SQL queries for joining streaming data with reference data

-- ============================================================================
-- 1. Reference Data - Users Table (JDBC or Kafka)
-- ============================================================================

CREATE TABLE users_reference (
    user_id BIGINT,
    username STRING,
    email STRING,
    created_at TIMESTAMP(3),
    last_active TIMESTAMP(3),
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:postgresql://postgres:5432/fotobook_development',
    'table-name' = 'users',
    'username' = 'fotobook',
    'password' = 'password',
    'lookup.cache.max-rows' = '10000',
    'lookup.cache.ttl' = '1h'
);

-- Alternative: From Kafka topic
-- CREATE TABLE users_reference (
--     user_id BIGINT,
--     username STRING,
--     email STRING,
--     created_at TIMESTAMP(3),
--     PRIMARY KEY (user_id) NOT ENFORCED
-- ) WITH (
--     'connector' = 'kafka',
--     'topic' = 'fotobook.users',
--     'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
--     'format' = 'json'
-- );

-- ============================================================================
-- 2. Enriched User Engagement with User Details
-- ============================================================================

CREATE TABLE enriched_user_engagement (
    user_id BIGINT,
    username STRING,
    email STRING,
    engagement_score DOUBLE,
    like_count BIGINT,
    view_count BIGINT,
    comment_count BIGINT,
    last_active TIMESTAMP(3),
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (user_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'enriched-user-engagement',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

-- Join user engagement with user reference data
INSERT INTO enriched_user_engagement
SELECT
    ue.user_id,
    u.username,
    u.email,
    ue.engagement_score,
    ue.like_count,
    ue.view_count,
    ue.comment_count,
    GREATEST(ue.window_end, u.last_active) AS last_active,
    ue.window_start,
    ue.window_end
FROM user_engagement_score AS ue
LEFT JOIN users_reference FOR SYSTEM_TIME AS OF ue.window_start AS u
    ON ue.user_id = u.user_id;

-- ============================================================================
-- 3. Enriched Popular Photos with Photo Details
-- ============================================================================

CREATE TABLE enriched_popular_photos (
    photo_id BIGINT,
    photo_title STRING,
    photo_owner_id BIGINT,
    photo_mode STRING,
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
    'topic' = 'enriched-popular-photos',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

-- Join popular photos with photo reference data
INSERT INTO enriched_popular_photos
SELECT
    pp.photo_id,
    p.title AS photo_title,
    p.user_id AS photo_owner_id,
    p.mode AS photo_mode,
    pp.rank_position,
    pp.popularity_score,
    pp.like_count,
    pp.view_count,
    pp.comment_count,
    pp.window_start,
    pp.window_end
FROM popular_photos_ranking AS pp
LEFT JOIN photos_reference FOR SYSTEM_TIME AS OF pp.window_start AS p
    ON pp.photo_id = p.photo_id;

-- ============================================================================
-- 4. User Preferences with Photo Details
-- ============================================================================

CREATE TABLE enriched_user_preferences (
    user_id BIGINT,
    username STRING,
    photo_id BIGINT,
    photo_title STRING,
    photo_owner_id BIGINT,
    preference_score DOUBLE,
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (user_id, photo_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'enriched-user-preferences',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO enriched_user_preferences
SELECT
    upv.user_id,
    u.username,
    upv.photo_id,
    p.title AS photo_title,
    p.user_id AS photo_owner_id,
    upv.preference_score,
    upv.window_start,
    upv.window_end
FROM user_preference_vectors AS upv
LEFT JOIN users_reference FOR SYSTEM_TIME AS OF upv.window_start AS u
    ON upv.user_id = u.user_id
LEFT JOIN photos_reference FOR SYSTEM_TIME AS OF upv.window_start AS p
    ON upv.photo_id = p.photo_id;