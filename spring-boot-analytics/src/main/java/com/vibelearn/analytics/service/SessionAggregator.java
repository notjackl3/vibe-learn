package com.vibelearn.analytics.service;

import com.vibelearn.analytics.model.CodeEvent;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * In-memory aggregator that accumulates events per session.
 * Thread-safe for concurrent event processing.
 *
 * Design Decision: Use in-memory aggregation instead of updating MongoDB on every event
 * Why? Reduces database writes by 1000x (from per-event to per-flush)
 * Trade-off: Risk of data loss if service crashes (mitigated by frequent flushes)
 */
@Slf4j
@Component
public class SessionAggregator {

    // Thread-safe map: sessionId -> aggregated data
    private final Map<String, SessionAggregate> sessionData = new ConcurrentHashMap<>();

    /**
     * Add an event to the in-memory aggregation
     */
    public void addEvent(CodeEvent event) {
        String sessionId = event.getSessionId();

        sessionData.compute(sessionId, (key, existing) -> {
            if (existing == null) {
                existing = new SessionAggregate(sessionId);
            }
            existing.addEvent(event);
            return existing;
        });

        log.debug("Aggregated event for session: {}, total events: {}",
                sessionId, sessionData.get(sessionId).getTotalEvents());
    }

    /**
     * Get all sessions that need flushing and clear them from memory
     */
    public Collection<SessionAggregate> flushAndClear() {
        log.info("Flushing {} sessions from memory", sessionData.size());

        // Create snapshot and clear
        Collection<SessionAggregate> snapshot = new ArrayList<>(sessionData.values());
        sessionData.clear();

        return snapshot;
    }

    /**
     * Get current state without clearing (for monitoring)
     */
    public Map<String, SessionAggregate> getCurrentState() {
        return new HashMap<>(sessionData);
    }

    /**
     * Inner class to hold aggregated data for one session
     */
    @Data
    public static class SessionAggregate {
        private final String sessionId;
        private Instant firstEventTime;
        private Instant lastEventTime;

        private int totalEvents = 0;
        private int totalLines = 0;

        private final Set<String> filesModified = new HashSet<>();
        private final Map<String, Integer> linesPerFile = new HashMap<>();
        private final Map<String, Integer> eventsBySource = new HashMap<>();

        // For calculating average time between events
        private final List<Long> eventTimestamps = new ArrayList<>();

        public SessionAggregate(String sessionId) {
            this.sessionId = sessionId;
        }

        public void addEvent(CodeEvent event) {
            totalEvents++;

            // Time tracking
            Instant eventTime = Instant.ofEpochMilli(event.getClientTimestampMs());
            if (firstEventTime == null) {
                firstEventTime = eventTime;
            }
            lastEventTime = eventTime;
            eventTimestamps.add(event.getClientTimestampMs());

            // File tracking
            String fileName = event.getFileName();
            if (fileName != null) {
                filesModified.add(fileName);
                // merge() means if key exists, add 1 to existing value,Ii key doesn't exist, insert with value 1
                linesPerFile.merge(fileName, 1, Integer::sum);
                totalLines++;
            }

            // Source tracking
            String source = event.getSource();
            if (source != null) {
                eventsBySource.merge(source, 1, Integer::sum);
            }
        }

        /**
         * Calculate metrics from accumulated data
         */
        public Map<String, Object> calculateMetrics() {
            Map<String, Object> metrics = new HashMap<>();

            if (firstEventTime != null && lastEventTime != null) {
                long durationSeconds = lastEventTime.getEpochSecond() - firstEventTime.getEpochSecond();
                metrics.put("durationSeconds", Math.max(1, durationSeconds));

                double durationMinutes = durationSeconds / 60.0;
                if (durationMinutes > 0) {
                    metrics.put("linesPerMinute", totalLines / durationMinutes);
                    metrics.put("eventsPerMinute", totalEvents / durationMinutes);
                }
            }

            // Average time between events
            if (eventTimestamps.size() > 1) {
                long totalGap = 0;
                for (int i = 1; i < eventTimestamps.size(); i++) {
                    totalGap += (eventTimestamps.get(i) - eventTimestamps.get(i - 1));
                }
                metrics.put("averageTimeBetweenEvents", totalGap / (double) (eventTimestamps.size() - 1));
            }

            // Most edited file
            if (!linesPerFile.isEmpty()) {
                Map.Entry<String, Integer> max = linesPerFile.entrySet().stream()
                        .max(Map.Entry.comparingByValue())
                        .orElse(null);
                if (max != null) {
                    metrics.put("mostEditedFile", max.getKey());
                    metrics.put("mostEditedFileLines", max.getValue());
                }
            }

            return metrics;
        }
    }
}