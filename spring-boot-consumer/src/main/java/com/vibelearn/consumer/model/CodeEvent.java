package com.vibelearn.consumer.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.Indexed;

/**
 * MongoDB document representing a code event.
 * Stored in the "events" collection.
 */
@Document(collection = "events")  // MongoDB collection name
@Data
@NoArgsConstructor
@AllArgsConstructor
public class CodeEvent {

    @Id  // MongoDB _id field (auto-generated if null)
    private String id;

    @Indexed  // Create index for faster queries by sessionId
    private String sessionId;

    private Long clientTimestampMs;
    private Long serverTimestampMs;

    @Indexed
    private String fileUri;

    private String fileName;
    private Integer lineNumber;
    private String textNormalized;
    private String source;

    // Timestamp when saved to MongoDB
    private Long savedTimestampMs;
}