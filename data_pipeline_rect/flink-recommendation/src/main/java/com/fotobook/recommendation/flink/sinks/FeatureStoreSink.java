package com.fotobook.recommendation.flink.sinks;

import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.URI;
import java.time.Duration;

/**
 * Feature Store sink for storing aggregated features
 */
public class FeatureStoreSink<T> extends RichSinkFunction<T> {
    private static final Logger LOG = LoggerFactory.getLogger(FeatureStoreSink.class);

    private final String featureStoreUrl;
    private final String featureGroup;
    private transient HttpClient httpClient;
    private transient ObjectMapper objectMapper;

    public FeatureStoreSink(String featureStoreUrl, String featureGroup) {
        this.featureStoreUrl = featureStoreUrl;
        this.featureGroup = featureGroup;
    }

    @Override
    public void open(Configuration parameters) throws Exception {
        super.open(parameters);
        this.httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public void invoke(T value, Context context) throws Exception {
        try {
            String jsonValue = objectMapper.writeValueAsString(value);
            String url = String.format("%s/api/v1/features/%s", featureStoreUrl, featureGroup);

            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(jsonValue))
                .timeout(Duration.ofSeconds(5))
                .build();

            HttpResponse<String> response = httpClient.send(request, 
                HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                LOG.debug("Stored feature in Feature Store: group={}, value={}", 
                    featureGroup, jsonValue);
            } else {
                LOG.warn("Failed to store feature in Feature Store: status={}, body={}",
                    response.statusCode(), response.body());
            }
        } catch (Exception e) {
            LOG.error("Error storing feature in Feature Store", e);
            // In production, consider sending to DLQ
        }
    }
}