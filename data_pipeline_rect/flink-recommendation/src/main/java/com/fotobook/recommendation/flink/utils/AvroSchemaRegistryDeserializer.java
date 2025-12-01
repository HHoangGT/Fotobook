package com.fotobook.recommendation.flink.utils;

import io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient;
import io.confluent.kafka.schemaregistry.client.SchemaRegistryClient;
import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.api.java.typeutils.TypeExtractor;
import org.apache.kafka.common.serialization.Deserializer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;

/**
 * Avro deserializer with Schema Registry support
 */
public class AvroSchemaRegistryDeserializer<T> implements DeserializationSchema<T> {
    private static final Logger LOG = LoggerFactory.getLogger(AvroSchemaRegistryDeserializer.class);

    private final Class<T> typeClass;
    private final String schemaRegistryUrl;
    private final String subject;
    
    private transient KafkaAvroDeserializer deserializer;
    private transient SchemaRegistryClient schemaRegistryClient;

    public AvroSchemaRegistryDeserializer(Class<T> typeClass, String schemaRegistryUrl, String subject) {
        this.typeClass = typeClass;
        this.schemaRegistryUrl = schemaRegistryUrl;
        this.subject = subject;
        
        // Initialize deserializer
        Map<String, Object> props = new HashMap<>();
        props.put("schema.registry.url", schemaRegistryUrl);
        
        this.schemaRegistryClient = new CachedSchemaRegistryClient(schemaRegistryUrl, 100);
        this.deserializer = new KafkaAvroDeserializer(schemaRegistryClient, props);
    }

    @Override
    public T deserialize(byte[] message) throws IOException {
        try {
            Object deserialized = deserializer.deserialize(subject, message);
            
            if (deserialized == null) {
                return null;
            }

            // Convert to target type
            return typeClass.cast(deserialized);
        } catch (Exception e) {
            LOG.error("Error deserializing Avro message", e);
            throw new IOException("Failed to deserialize Avro message", e);
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