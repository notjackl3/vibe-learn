package com.vibelearn.ingest.service;

import org.springframework.stereotype.Service;
import com.vibelearn.ingest.model.CodeEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.util.concurrent.CompletableFuture;

@Service
@RequiredArgsConstructor 
@Slf4j
public class EventProducerService {

    // Injected by Spring (configured in KafkaProducerConfig)
    private final KafkaTemplate<String, CodeEvent> kafkaTemplate;
    
    // Reads from application.yml: kafka.topic.code-events
    @Value("${kafka.topic.code-events}")
    private String topicName;

    // Send the event to Kafka asynchronously
    public void sendEvent(CodeEvent event) {
        // Use sessionId as the Kafka message key (ensures events from same session 
        // go to same partition, maintaining order)
        String key = event.getSessionId();
        
        // Send asynchronously - returns immediately, doesn't wait for Kafka
        CompletableFuture<SendResult<String, CodeEvent>> future = 
            kafkaTemplate.send(topicName, key, event);
        
        // Add callback to log success/failure (executed when Kafka responds)
        future.whenComplete((result, ex) -> {
            if (ex == null) {
                log.debug("Event sent successfully: session={}, line={}, partition={}, offset={}", 
                         event.getSessionId(), 
                         event.getLineNumber(),
                         result.getRecordMetadata().partition(),
                         result.getRecordMetadata().offset());
            } else {
                log.error("Failed to send event: session={}, file={}, error={}", 
                         event.getSessionId(), 
                         event.getFileName(), 
                         ex.getMessage());
            }
        });
    }
}
