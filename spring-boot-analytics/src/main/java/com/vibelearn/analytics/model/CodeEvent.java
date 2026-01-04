package com.vibelearn.analytics.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Represents a code event consumed from Kafka.
 * Mirrors the event structure from the producer.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class CodeEvent {
    // No need to CodeEvent @Id analytics do not need to store
    // events, only use them to calculate metrics
    private String sessionId;
    private Long clientTimestampMs;
    private Long serverTimestampMs;
    private String fileUri;
    private String fileName;
    private Integer lineNumber;
    private String textNormalized;
    private String source;
}