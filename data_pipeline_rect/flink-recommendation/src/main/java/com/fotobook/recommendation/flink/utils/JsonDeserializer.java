package com.fotobook.recommendation.flink.utils;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.api.java.typeutils.TypeExtractor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;

/**
 * JSON deserializer for Flink Kafka consumer
 */
public class JsonDeserializer<T> implements DeserializationSchema<T> {
    private static final Logger LOG = LoggerFactory.getLogger(JsonDeserializer.class);

    private final Class<T> typeClass;
    private transient ObjectMapper objectMapper;

    public JsonDeserializer(Class<T> typeClass) {
        this.typeClass = typeClass;
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public T deserialize(byte[] message) throws IOException {
        try {
            if (message == null || message.length == 0) {
                return null;
            }
            return objectMapper.readValue(message, typeClass);
        } catch (Exception e) {
            LOG.error("Error deserializing JSON message", e);
            // Return null to skip invalid messages (can also throw to fail job)
            return null;
        }
    }

    @Override
    public boolean isEndOfStream(T nextElement) {
        return false;
    }

    @Override
    public TypeInformation<T> getProducedType() {
        return TypeExtractor.getForClass(typeClass);
    }
}
