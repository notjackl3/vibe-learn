package com.vibelearn.consumer.service;

import com.vibelearn.consumer.model.CodeEvent;
import com.vibelearn.consumer.repository.EventRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Service;

/**
 * Consumes code events from Kafka and persists them to MongoDB.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class EventConsumerService {

    private final EventRepository eventRepository;

    /**
     * Listens to the "code_events" Kafka topic.
     * Automatically triggered when new messages arrive.
     * 
     * @param event The deserialized CodeEvent
     * @param partition Which Kafka partition the message came from
     * @param offset The message offset in the partition
     */
    @KafkaListener(
        topics = "${kafka.topic.code-events}",  // From application.yml
        groupId = "${spring.kafka.consumer.group-id}"
    )
    public void consumeEvent(
            @Payload CodeEvent event,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.OFFSET) long offset) {
        
        log.info("Received event from Kafka: session={}, file={}, line={}, partition={}, offset={}", 
                 event.getSessionId(), 
                 event.getFileName(), 
                 event.getLineNumber(),
                 partition,
                 offset);
        
        try {
            // Add timestamp for when we saved to MongoDB
            event.setSavedTimestampMs(System.currentTimeMillis());
            
            // Save to MongoDB (upsert if exists, insert if new)
            CodeEvent savedEvent = eventRepository.save(event);
            
            log.debug("Event saved to MongoDB with id: {}", savedEvent.getId());
            
        } catch (Exception e) {
            log.error("Failed to save event to MongoDB: session={}, error={}", 
                     event.getSessionId(), e.getMessage(), e);
            
            // In production, you might want to:
            // - Send to dead-letter queue
            // - Retry with backoff
            // - Alert monitoring system
            throw e;  // Let Kafka retry if configured
        }
    }
    
    /**
     * Optional: Handle batch consumption for better performance.
     * Uncomment if you want to process messages in batches.
     */
    /*
    @KafkaListener(
        topics = "${kafka.topic.code-events}",
        groupId = "${spring.kafka.consumer.group-id}",
        containerFactory = "batchKafkaListenerContainerFactory"
    )
    public void consumeEventBatch(List<CodeEvent> events) {
        log.info("Received batch of {} events", events.size());
        
        events.forEach(event -> 
            event.setSavedTimestampMs(System.currentTimeMillis())
        );
        
        eventRepository.saveAll(events);
        log.info("Saved {} events to MongoDB", events.size());
    }
    */
}