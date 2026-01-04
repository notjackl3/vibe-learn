package com.vibelearn.consumer.service;

import com.vibelearn.consumer.model.CodeEvent;
import com.vibelearn.consumer.repository.EventRepository;
import lombok.extern.slf4j.Slf4j;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Service;

@Service
@Slf4j
public class EventConsumerService {

    private final EventRepository eventRepository;
    private final MeterRegistry meterRegistry;

    // Metrics
    private final Counter eventsProcessed;
    private final Counter processingErrors;

    public EventConsumerService(EventRepository eventRepository, MeterRegistry meterRegistry) {
        this.eventRepository = eventRepository;
        this.meterRegistry = meterRegistry;

        // Initialize metrics
        this.eventsProcessed = Counter.builder("consumer.events.processed")
                .description("Total events processed by consumer")
                .register(meterRegistry);

        this.processingErrors = Counter.builder("consumer.events.errors")
                .description("Total errors processing events")
                .register(meterRegistry);
    }

    // Original listener
    @KafkaListener(
        topics = "${kafka.topic.code-events}",
        groupId = "${spring.kafka.consumer.group-id}",
        containerFactory = "kafkaListenerContainerFactory"
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

            eventsProcessed.increment();
            
        } catch (Exception e) {
            log.error("Failed to save event to MongoDB: session={}, error={}", 
                     event.getSessionId(), e.getMessage(), e);

            processingErrors.increment();

            throw e;
        }
    }
}