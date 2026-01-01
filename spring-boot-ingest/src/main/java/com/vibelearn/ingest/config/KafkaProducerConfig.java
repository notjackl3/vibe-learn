package com.vibelearn.ingest.config;

import com.vibelearn.ingest.model.CodeEvent;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.core.ProducerFactory;
import org.springframework.kafka.support.serializer.JacksonJsonSerializer;

import java.util.HashMap;
import java.util.Map;

// Configures Kafka producer for sending code events
@Configuration  // Tells Spring: this class contains bean definitions
public class KafkaProducerConfig {

    @Value("${spring.kafka.bootstrap-servers}")
    private String bootstrapServers;  // Kafka address from application.yml

    /**
     * Creates the factory that produces Kafka producer instances.
     * Think of this as a "Kafka producer builder".
     */
    @Bean
    public ProducerFactory<String, CodeEvent> producerFactory() {
        Map<String, Object> configProps = new HashMap<>();
        // Where is Kafka? (e.g., localhost:9094)
        configProps.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        // How to serialize the message KEY (sessionId) - as String
        configProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        // How to serialize the message VALUE (CodeEvent) - as JSON
        configProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JacksonJsonSerializer.class);
        // Don't add Java type info to JSON (keeps it clean)
        configProps.put(JacksonJsonSerializer.ADD_TYPE_INFO_HEADERS, false); 
        // Reliability settings
        configProps.put(ProducerConfig.ACKS_CONFIG, "1");  // Wait for leader acknowledgment
        configProps.put(ProducerConfig.RETRIES_CONFIG, 3);  // Retry 3 times on failure
        configProps.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);
        return new DefaultKafkaProducerFactory<>(configProps);
    }

    /**
     * Creates the KafkaTemplate used to send messages.
     * This is what EventProducerService injects and uses.
     */
    @Bean
    public KafkaTemplate<String, CodeEvent> kafkaTemplate() {
        return new KafkaTemplate<>(producerFactory());
    }
}