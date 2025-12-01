-- Feature Store Schema for Recommendation System

-- User Features Table
CREATE TABLE IF NOT EXISTS user_features (
    user_id BIGINT PRIMARY KEY,
    engagement_score DOUBLE PRECISION,
    preference_vector JSONB,
    last_active TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Photo Features Table
CREATE TABLE IF NOT EXISTS photo_features (
    photo_id BIGINT PRIMARY KEY,
    popularity_score DOUBLE PRECISION,
    like_count_1h BIGINT,
    like_count_24h BIGINT,
    view_count_24h BIGINT,
    comment_count_24h BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User-Photo Features Table (Interaction Scores)
CREATE TABLE IF NOT EXISTS user_photo_features (
    user_id BIGINT,
    photo_id BIGINT,
    interaction_score DOUBLE PRECISION,
    predicted_rating DOUBLE PRECISION,
    last_interaction TIMESTAMP,
    PRIMARY KEY (user_id, photo_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User Similarity Matrix Table
CREATE TABLE IF NOT EXISTS user_similarity_matrix (
    user1_id BIGINT,
    user2_id BIGINT,
    similarity_score DOUBLE PRECISION,
    window_start TIMESTAMP,
    window_end TIMESTAMP,
    PRIMARY KEY (user1_id, user2_id, window_start),
    INDEX idx_user1 (user1_id),
    INDEX idx_user2 (user2_id)
);

-- Photo Co-occurrence Matrix Table
CREATE TABLE IF NOT EXISTS photo_cooccurrence_matrix (
    photo1_id BIGINT,
    photo2_id BIGINT,
    cooccurrence_count BIGINT,
    window_start TIMESTAMP,
    window_end TIMESTAMP,
    PRIMARY KEY (photo1_id, photo2_id, window_start)
);

-- Popular Photos Ranking Table
CREATE TABLE IF NOT EXISTS popular_photos_ranking (
    photo_id BIGINT,
    rank_position BIGINT,
    popularity_score DOUBLE PRECISION,
    like_count BIGINT,
    view_count BIGINT,
    comment_count BIGINT,
    window_start TIMESTAMP,
    window_end TIMESTAMP,
    PRIMARY KEY (photo_id, window_start),
    INDEX idx_rank (rank_position, window_start)
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_user_features_engagement ON user_features(engagement_score DESC);
CREATE INDEX IF NOT EXISTS idx_photo_features_popularity ON photo_features(popularity_score DESC);
CREATE INDEX IF NOT EXISTS idx_user_photo_score ON user_photo_features(interaction_score DESC);