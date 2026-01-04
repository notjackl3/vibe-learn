package com.vibelearn.consumer.service;

import com.vibelearn.consumer.model.CodeEvent;
import com.vibelearn.consumer.repository.EventRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Service;

@Service
@Slf4j
public class EventConsumerService {

    private final EventRepository eventRepository;

    public EventConsumerService(EventRepository eventRepository) {
        this.eventRepository = eventRepository;
        log.info("========================================");
        log.info("EventConsumerService BEAN CREATED!");
        log.info("========================================");
    }

    // TEST LISTENER - receives raw string to see if listener works at all
    @KafkaListener(
        topics = "${kafka.topic.code-events}",
        groupId = "event-consumer-group",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void testRawConsumer(String rawMessage) {
        log.info("========== RAW MESSAGE RECEIVED ==========");
        log.info("Raw Message: {}", rawMessage);
        log.info("==========================================");
    }

    // Original listener
    @KafkaListener(
        topics = "${kafka.topic.code-events}",
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
            event.setSavedTimestampMs(System.currentTimeMillis());
            CodeEvent savedEvent = eventRepository.save(event);
            log.debug("Event saved to MongoDB with id: {}", savedEvent.getId());
            
        } catch (Exception e) {
            log.error("Failed to save event to MongoDB: session={}, error={}", 
                     event.getSessionId(), e.getMessage(), e);
            throw e;
        }
    }
}