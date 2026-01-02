package com.vibelearn.consumer.controller;

import com.vibelearn.consumer.model.CodeEvent;
import com.vibelearn.consumer.repository.EventRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/test")
@RequiredArgsConstructor
@Slf4j
public class TestController {

    private final EventRepository eventRepository;

    @PostMapping("/save")
    public CodeEvent testSave() {
        log.info("========== TEST SAVE CALLED ==========");

        CodeEvent event = new CodeEvent();
        event.setSessionId("REST-TEST");
        event.setClientTimestampMs(1704211200000L);
        event.setServerTimestampMs(1704211200000L);
        event.setFileUri("file:///rest-test.js");
        event.setFileName("RestTest.java");
        event.setLineNumber(456);
        event.setTextNormalized("System.out.println('REST TEST');");
        event.setSource("rest-endpoint");
        event.setSavedTimestampMs(System.currentTimeMillis());

        CodeEvent saved = eventRepository.save(event);
        log.info("Saved event with ID: {}", saved.getId());

        return saved;
    }
}