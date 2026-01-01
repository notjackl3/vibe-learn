package com.vibelearn.ingest.controller;

import org.springframework.web.bind.annotation.RestController;
import com.vibelearn.ingest.model.CodeEvent;
import com.vibelearn.ingest.service.EventProducerService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

// Validate the incoming JSON, create timestamp, and tell EventProducerServic to send to Kafka
@RestController
@RequestMapping("/api") // all endpoints start with /api
@RequiredArgsConstructor // use Lombok to create a constructor for the class (dependency injection)
@Slf4j // create a logger for this class
public class EventController {
    private final EventProducerService eventProducerService; // inject the EventProducerService

    // Receive the event from the VS Code extension, the code event is validated and then sent to Kafka
    @PostMapping("/events")
    public ResponseEntity<?> receiveEvent(@Valid @RequestBody CodeEvent event) {
        
        log.info("Received event for session: {}, file: {}, line: {}", 
                 event.getSessionId(), event.getFileName(), event.getLineNumber());
        
        // Add server-side timestamp (when we received it)
        event.setServerTimestampMs(System.currentTimeMillis());
        
        try {
            // Send to Kafka (async operation)
            eventProducerService.sendEvent(event);
            
            // Respond to extension immediately (don't wait for Kafka)
            return ResponseEntity.ok()
                .body(new Response("Event received successfully", event.getSessionId()));
                
        } catch (Exception e) {
            log.error("Failed to process event: {}", e.getMessage());
            return ResponseEntity.internalServerError()
                .body(new ErrorResponse("Failed to process event", e.getMessage()));
        }
    }
    
    // Simple response DTOs (Data Transfer Objects)
    record Response(String message, String sessionId) {}
    record ErrorResponse(String error, String details) {}
}


