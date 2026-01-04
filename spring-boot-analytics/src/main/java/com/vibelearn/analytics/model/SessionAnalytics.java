package com.vibelearn.analytics.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.Indexed;

import java.time.Instant;
import java.util.Map;
import java.util.Set;

/**
 * Aggregated analytics for a coding session.
 * Stored in 'session_analytics' collection for fast queries.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder // Allows SessionAnalytics.builder().field(value).build()
@Document(collection = "session_analytics")
public class SessionAnalytics {

    @Id
    private String id;

    @Indexed(unique = true)
    private String sessionId;

    // Time tracking
    private Instant sessionStart;
    private Instant sessionEnd;
    private Instant lastUpdated;
    private Long durationSeconds;

    // Event counts
    private Integer totalEvents;
    private Integer totalLines;

    // Unique files tracking
    private Set<String> filesModified;
    private Integer uniqueFilesCount;

    // Performance metrics
    private Double linesPerMinute;
    private Double eventsPerMinute;
    private Double averageTimeBetweenEvents; // milliseconds

    // File-level breakdown
    private Map<String, Integer> linesPerFile;  // fileName : line count
    private String mostEditedFile;
    private Integer mostEditedFileLines;

    // Source breakdown (manual, jmeter, extension, etc)
    private Map<String, Integer> eventsBySource;
}