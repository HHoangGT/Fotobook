package com.fotobook.recommendation.flink.sinks;

import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPool;
import redis.clients.jedis.JedisPoolConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Redis sink for storing feature values
 */
public class RedisFeatureSink<T> extends RichSinkFunction<T> {
    private static final Logger LOG = LoggerFactory.getLogger(RedisFeatureSink.class);

    private final String redisHost;
    private final int redisPort;
    private final String keyPrefix;
    private transient JedisPool jedisPool;
    private transient ObjectMapper objectMapper;

    public RedisFeatureSink(String redisHost, int redisPort, String keyPrefix) {
        this.redisHost = redisHost;
        this.redisPort = redisPort;
        this.keyPrefix = keyPrefix;
    }

    @Override
    public void open(Configuration parameters) throws Exception {
        super.open(parameters);
        JedisPoolConfig poolConfig = new JedisPoolConfig();
        poolConfig.setMaxTotal(10);
        poolConfig.setMaxIdle(5);
        poolConfig.setMinIdle(2);
        
        this.jedisPool = new JedisPool(poolConfig, redisHost, redisPort);
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public void invoke(T value, Context context) throws Exception {
        try (Jedis jedis = jedisPool.getResource()) {
            String key = generateKey(value);
            String jsonValue = objectMapper.writeValueAsString(value);
            
            // Store with TTL (24 hours)
            jedis.setex(key, 86400, jsonValue);
            
            LOG.info("✅ Stored feature in Redis: key={}, value={}", key, jsonValue);
        } catch (Exception e) {
            // Don't throw exception to prevent job restart
            // Just log the error and continue processing
            LOG.error("Error storing feature in Redis: key={}, value={}", 
                value != null ? generateKey(value) : "unknown", 
                value != null ? value.toString() : "null", e);
        }
    }

    private String generateKey(T value) {
        // Generate Redis key based on value type and key prefix
        // This is a simplified version - adjust based on your models
        if (value instanceof com.fotobook.recommendation.flink.models.PhotoLikeCount) {
            com.fotobook.recommendation.flink.models.PhotoLikeCount plc = 
                (com.fotobook.recommendation.flink.models.PhotoLikeCount) value;
            return String.format("%s:%d", keyPrefix, plc.getPhotoId());
        } else if (value instanceof com.fotobook.recommendation.flink.models.UserEngagementScore) {
            com.fotobook.recommendation.flink.models.UserEngagementScore ues = 
                (com.fotobook.recommendation.flink.models.UserEngagementScore) value;
            return String.format("%s:%d", keyPrefix, ues.getUserId());
        }
        
        return keyPrefix + ":" + value.hashCode();
    }

    @Override
    public void close() throws Exception {
        super.close();
        if (jedisPool != null) {
            jedisPool.close();
        }
    }
}