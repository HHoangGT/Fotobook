-- ============================================================================
-- Real-time Aggregations - Flink SQL Queries
-- ============================================================================
-- Additional real-time aggregation queries for dashboard and monitoring

-- ============================================================================
-- 1. Real-time Activity Rate per Minute
-- ============================================================================

CREATE TABLE activity_rate_per_minute (
    activity_type STRING,
    target_type STRING,
    activity_count BIGINT,
    minute_start TIMESTAMP(3),
    PRIMARY KEY (activity_type, target_type, minute_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'activity-rate-per-minute',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO activity_rate_per_minute
SELECT
    activity_type,
    target_type,
    COUNT(*) AS activity_count,
    TUMBLE_START(event_time, INTERVAL '1' MINUTE) AS minute_start
FROM user_activities_source
WHERE _op != 'd'
GROUP BY
    activity_type,
    target_type,
    TUMBLE(event_time, INTERVAL '1' MINUTE);

-- ============================================================================
-- 2. Top Active Users - Sliding Window 1 Hour
-- ============================================================================

CREATE TABLE top_active_users (
    user_id BIGINT,
    activity_count BIGINT,
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (user_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'top-active-users',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO top_active_users
SELECT
    user_id,
    COUNT(*) AS activity_count,
    HOP_START(event_time, INTERVAL '10' MINUTE, INTERVAL '1' HOUR) AS window_start,
    HOP_END(event_time, INTERVAL '10' MINUTE, INTERVAL '1' HOUR) AS window_end
FROM user_activities_source
WHERE _op != 'd'
GROUP BY
    user_id,
    HOP(event_time, INTERVAL '10' MINUTE, INTERVAL '1' HOUR);

-- ============================================================================
-- 3. Photo View Count - Real-time (Last 24 hours)
-- ============================================================================

CREATE TABLE photo_view_count_24h (
    photo_id BIGINT,
    view_count BIGINT,
    last_view_time TIMESTAMP(3),
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    PRIMARY KEY (photo_id, window_start) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'photo-view-count-24h',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

INSERT INTO photo_view_count_24h
SELECT
    target_id AS photo_id,
    COUNT(*) AS view_count,
    MAX(event_time) AS last_view_time,
    HOP_START(event_time, INTERVAL '1' HOUR, INTERVAL '24' HOUR) AS window_start,
    HOP_END(event_time, INTERVAL '1' HOUR, INTERVAL '24' HOUR) AS window_end
FROM user_activities_source
WHERE activity_type = 'VIEW' 
  AND target_type = 'photo'
  AND _op != 'd'
GROUP BY
    target_id,
    HOP(event_time, INTERVAL '1' HOUR, INTERVAL '24' HOUR);

-- ============================================================================
-- 4. User Activity Timeline - Session-based
-- ============================================================================

CREATE TABLE user_activity_sessions (
    user_id BIGINT,
    session_id STRING,
    session_start TIMESTAMP(3),
    session_end TIMESTAMP(3),
    activity_count BIGINT,
    PRIMARY KEY (user_id, session_id) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'user-activity-sessions',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

-- Session: activities within 30 minutes are considered one session
INSERT INTO user_activity_sessions
SELECT
    user_id,
    CAST(FLOOR(UNIX_TIMESTAMP(event_time) / 1800) AS STRING) AS session_id,
    MIN(event_time) AS session_start,
    MAX(event_time) AS session_end,
    COUNT(*) AS activity_count
FROM user_activities_source
WHERE _op != 'd'
GROUP BY
    user_id,
    FLOOR(UNIX_TIMESTAMP(event_time) / 1800);

-- ============================================================================
-- 5. Aggregate Statistics - Dashboard Metrics
-- ============================================================================

CREATE TABLE dashboard_metrics (
    metric_name STRING,
    metric_value DOUBLE,
    metric_timestamp TIMESTAMP(3),
    PRIMARY KEY (metric_name, metric_timestamp) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'dashboard-metrics',
    'properties.bootstrap.servers' = 'kafka-1:29092,kafka-2:29092,kafka-3:29092',
    'key.format' = 'json',
    'value.format' = 'json'
);

-- Total active users in last hour
INSERT INTO dashboard_metrics
SELECT
    'total_active_users_1h' AS metric_name,
    CAST(COUNT(DISTINCT user_id) AS DOUBLE) AS metric_value,
    TUMBLE_START(event_time, INTERVAL '1' MINUTE) AS metric_timestamp
FROM user_activities_source
WHERE _op != 'd'
  AND event_time >= CURRENT_TIMESTAMP - INTERVAL '1' HOUR
GROUP BY TUMBLE(event_time, INTERVAL '1' MINUTE);

-- Total likes in last hour
INSERT INTO dashboard_metrics
SELECT
    'total_likes_1h' AS metric_name,
    CAST(COUNT(*) AS DOUBLE) AS metric_value,
    TUMBLE_START(event_time, INTERVAL '1' MINUTE) AS metric_timestamp
FROM user_activities_source
WHERE activity_type = 'LIKE'
  AND _op != 'd'
  AND event_time >= CURRENT_TIMESTAMP - INTERVAL '1' HOUR
GROUP BY TUMBLE(event_time, INTERVAL '1' MINUTE);