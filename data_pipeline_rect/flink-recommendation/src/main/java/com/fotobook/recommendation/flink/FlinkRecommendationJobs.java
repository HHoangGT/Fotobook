package com.fotobook.recommendation.flink;

import com.fotobook.recommendation.flink.jobs.*;
import org.apache.flink.api.common.restartstrategy.RestartStrategies;
import org.apache.flink.api.common.time.Time;
import org.apache.flink.runtime.state.hashmap.HashMapStateBackend;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.environment.CheckpointConfig;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.configuration.RestOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.apache.flink.streaming.api.CheckpointingMode;
import java.util.concurrent.TimeUnit;

/**
 * Main entry point for Flink Recommendation Jobs
 */
public class FlinkRecommendationJobs {
    private static final Logger LOG = LoggerFactory.getLogger(FlinkRecommendationJobs.class);

    public static void main(String[] args) throws Exception {
        // Parse job type from arguments
        String jobType = args.length > 0 ? args[0] : "all";

        switch (jobType) {
            case "user-activity":
                runUserActivityJob();
                break;
            case "user-photo-interaction":
                runUserPhotoInteractionJob();
                break;
            case "feed-view":
                // TODO: Implement FeedViewAnalysisJob
                LOG.warn("Feed View Analysis Job is not yet implemented");
                // runFeedViewJob();
                break;
            case "all":
                // Note: Running multiple jobs in one JVM is not recommended for production
                // Each job should run in its own Flink cluster
                LOG.warn("Running all jobs sequentially - not recommended for production");
                runUserActivityJob();
                runUserPhotoInteractionJob();
                // runFeedViewJob(); // Commented out until implemented
                break;
            default:
                throw new IllegalArgumentException("Unknown job type: " + jobType);
        }
    }

    private static StreamExecutionEnvironment createExecutionEnvironment() {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // Enable checkpointing every 1 minute
        env.enableCheckpointing(60000); // 1 minute in milliseconds

        // Configure checkpointing
        CheckpointConfig checkpointConfig = env.getCheckpointConfig();
        checkpointConfig.setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);
        checkpointConfig.setMinPauseBetweenCheckpoints(500);
        checkpointConfig.setCheckpointTimeout(600000); // 10 minutes
        checkpointConfig.setMaxConcurrentCheckpoints(1);
        checkpointConfig.setExternalizedCheckpointCleanup(
            CheckpointConfig.ExternalizedCheckpointCleanup.RETAIN_ON_CANCELLATION
        );

        // State backend - HashMap
        env.setStateBackend(new HashMapStateBackend());
        // Use checkpoint storage that works in container
        checkpointConfig.setCheckpointStorage("file:///tmp/flink-checkpoints");

        // Restart strategy - more tolerant to prevent unnecessary restarts
        env.setRestartStrategy(
            RestartStrategies.fixedDelayRestart(
                10, // number of restart attempts (increased)
                Time.of(30, TimeUnit.SECONDS) // delay between restarts (increased)
            )
        );
        
        // Set parallelism
        env.setParallelism(4);

        // Watermark interval
        env.getConfig().setAutoWatermarkInterval(200); // 200ms

        // Parallelism
        env.setParallelism(4); // Can be overridden by config

        return env;
    }

    private static void runUserActivityJob() throws Exception {
        LOG.info("Starting User Activity Aggregation Job");
        StreamExecutionEnvironment env = createExecutionEnvironment();
        UserActivityAggregationJob job = new UserActivityAggregationJob();
        job.buildPipeline(env);
        env.execute("User Activity Aggregation Job");
    }

    private static void runUserPhotoInteractionJob() throws Exception {
        LOG.info("Starting User-Photo Interaction Job");
        StreamExecutionEnvironment env = createExecutionEnvironment();
        UserPhotoInteractionJob job = new UserPhotoInteractionJob();
        job.buildPipeline(env);
        env.execute("User-Photo Interaction Job");
    }

    // private static void runFeedViewJob() throws Exception {
    //     LOG.info("Starting Feed View Analysis Job");
    //     StreamExecutionEnvironment env = createExecutionEnvironment();
    //     FeedViewAnalysisJob job = new FeedViewAnalysisJob();
    //     job.buildPipeline(env);
    //     env.execute("Feed View Analysis Job");
    // }
}

