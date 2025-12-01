package com.fotobook.recommendation.flink.jobs;

import com.fotobook.recommendation.flink.models.PhotoInteraction;
import com.fotobook.recommendation.flink.models.UserPreferenceVector;
import com.fotobook.recommendation.flink.models.UserSimilarity;
import com.fotobook.recommendation.flink.models.PhotoCooccurrence;
import com.fotobook.recommendation.flink.functions.*;
import com.fotobook.recommendation.flink.sinks.FeatureStoreSink;
import com.fotobook.recommendation.flink.utils.AvroSchemaRegistryDeserializer;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;

/**
 * User-Photo Interaction Matrix Job
 * 
 * Processes photo_interactions topic and calculates:
 * - User similarity matrix (cosine similarity)
 * - Photo co-occurrence matrix
 * - User preference vectors
 */
public class UserPhotoInteractionJob {
    private static final Logger LOG = LoggerFactory.getLogger(UserPhotoInteractionJob.class);

    // Configuration
    private static final String KAFKA_BOOTSTRAP_SERVERS = "kafka-1:29092,kafka-2:29092,kafka-3:29092";
    private static final String SCHEMA_REGISTRY_URL = "http://schema-registry:8081";
    private static final String PHOTO_INTERACTIONS_TOPIC = "photo_interactions";
    private static final String FEATURE_STORE_URL = "http://feature-store:8080";

    public void buildPipeline(StreamExecutionEnvironment env) {
        // 1. Read from Kafka with Avro schema
        KafkaSource<PhotoInteraction> kafkaSource = KafkaSource.<PhotoInteraction>builder()
            .setBootstrapServers(KAFKA_BOOTSTRAP_SERVERS)
            .setTopics(PHOTO_INTERACTIONS_TOPIC)
            .setGroupId("flink-user-photo-interaction")
            .setStartingOffsets(OffsetsInitializer.latest())
            .setValueOnlyDeserializer(new AvroSchemaRegistryDeserializer<>(
                PhotoInteraction.class,
                SCHEMA_REGISTRY_URL,
                PHOTO_INTERACTIONS_TOPIC + "-value"
            ))
            .build();

        // 2. Create data stream with watermarks
        DataStream<PhotoInteraction> interactionStream = env
            .fromSource(kafkaSource,
                WatermarkStrategy
                    .<PhotoInteraction>forBoundedOutOfOrderness(Duration.ofSeconds(10))
                    .withTimestampAssigner((event, timestamp) -> event.getTimestamp()),
                "photo-interactions-source")
            .name("Photo Interactions Source");

        // 3. Filter valid interactions
        DataStream<PhotoInteraction> validInteractions = interactionStream
            .filter(interaction -> interaction.getInteractionType() != null &&
                                  !"UNLIKE".equals(interaction.getInteractionType().toString()))
            .name("Filter Valid Interactions");

        // 4. Build User Preference Vectors
        DataStream<UserPreferenceVector> userPreferences = validInteractions
            .keyBy(PhotoInteraction::getUserId)
            .window(TumblingEventTimeWindows.of(Time.hours(1)))
            .aggregate(new UserPreferenceVectorAggregator())
            .name("User Preference Vectors");

        // 5. Calculate User Similarity Matrix (Cosine Similarity)
        DataStream<UserSimilarity> userSimilarity = userPreferences
            .windowAll(TumblingEventTimeWindows.of(Time.hours(1)))
            .process(new UserSimilarityCalculator())
            .name("User Similarity Matrix");

        // 6. Calculate Photo Co-occurrence Matrix
        DataStream<PhotoCooccurrence> photoCooccurrence = validInteractions
            .keyBy(PhotoInteraction::getUserId)
            .window(TumblingEventTimeWindows.of(Time.hours(6)))
            .process(new PhotoCooccurrenceProcessor())
            .name("Photo Co-occurrence Matrix");

        // 7. Sink to Feature Store
        userPreferences.addSink(new FeatureStoreSink<>(
            FEATURE_STORE_URL,
            "user_preference_vectors"
        )).name("Feature Store Sink - User Preferences");

        userSimilarity.addSink(new FeatureStoreSink<>(
            FEATURE_STORE_URL,
            "user_similarity_matrix"
        )).name("Feature Store Sink - User Similarity");

        photoCooccurrence.addSink(new FeatureStoreSink<>(
            FEATURE_STORE_URL,
            "photo_cooccurrence_matrix"
        )).name("Feature Store Sink - Photo Co-occurrence");
    }
}