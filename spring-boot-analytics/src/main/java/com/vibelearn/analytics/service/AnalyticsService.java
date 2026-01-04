package com.vibelearn.analytics.service;

import com.vibelearn.analytics.model.CodeEvent;
import com.vibelearn.analytics.model.SessionAnalytics;
import com.vibelearn.analytics.repository.SessionAnalyticsRepository;
import com.vibelearn.analytics.service.SessionAggregator.SessionAggregate;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Collection;
import java.util.Map;

/**
 * Main analytics service that:
 * 1. Consumes events from Kafka
 * 2. Aggregates them in memory
 * 3. Periodically flushes to MongoDB
 */
@Service
@Slf4j
public class AnalyticsService {

    private final SessionAggregator aggregator;
    private final SessionAnalyticsRepository analyticsRepository;

    // Metrics for monitoring
    private final Counter eventsProcessed;
    private final Counter analyticsFlushes;

    public AnalyticsService(
            SessionAggregator aggregator,
            SessionAnalyticsRepository analyticsRepository,
            MeterRegistry meterRegistry) {
        this.aggregator = aggregator;
        this.analyticsRepository = analyticsRepository;

        // Register custom metrics
        this.eventsProcessed = Counter.builder("analytics.events.processed")
                .description("Total events processed by analytics service")
                .register(meterRegistry);

        this.analyticsFlushes = Counter.builder("analytics.flushes")
                .description("Number of times analytics were flushed to MongoDB")
                .register(meterRegistry);
    }

    /**
     * Consume events from Kafka.
     */
    @KafkaListener(
            topics = "${kafka.topic.code-events}",
            groupId = "${spring.kafka.consumer.group-id}",
            concurrency = "1"  // Single consumer for simplicity
    )
    public void consumeEvent(CodeEvent event) {
        log.debug("Analytics received event: session={}, file={}",
                event.getSessionId(), event.getFileName());

        try {
            aggregator.addEvent(event);
            eventsProcessed.increment();

        } catch (Exception e) {
            log.error("Failed to aggregate event: session={}, error={}",
                    event.getSessionId(), e.getMessage(), e);
            // Don't throw - continue processing other events
        }
    }

    /**
     * Periodically flush aggregated data to MongoDB.
     *
     * Design Decision: Fixed-rate scheduling instead of event-driven
     * Why? Predictable write patterns, easier to monitor
     * Trade-off: Might flush with no data (fine) or delay insights (acceptable)
     */
    @Scheduled(fixedRateString = "${analytics.flush-interval-seconds}000")
    public void flushAnalytics() {
        log.info("Starting scheduled analytics flush");

        Collection<SessionAggregate> sessions = aggregator.flushAndClear();

        if (sessions.isEmpty()) {
            log.debug("No sessions to flush");
            return;
        }

        int saved = 0;
        int failed = 0;

        for (SessionAggregate session : sessions) {
            try {
                SessionAnalytics analytics = buildAnalytics(session);

                // Upsert: update if exists, insert if new
                analyticsRepository.findBySessionId(session.getSessionId())
                        .ifPresentOrElse(
                                existing -> {
                                    // Merge with existing data
                                    mergeAnalytics(existing, analytics);
                                    analyticsRepository.save(existing);
                                },
                                () -> analyticsRepository.save(analytics)
                        );

                saved++;

            } catch (Exception e) {
                log.error("Failed to save analytics for session: {}, error={}",
                        session.getSessionId(), e.getMessage(), e);
                failed++;
            }
        }

        analyticsFlushes.increment();
        log.info("Flushed analytics: {} saved, {} failed", saved, failed);
    }

    /**
     * Build SessionAnalytics from aggregated data
     */
    private SessionAnalytics buildAnalytics(SessionAggregate session) {
        Map<String, Object> metrics = session.calculateMetrics();

        return SessionAnalytics.builder()
                .sessionId(session.getSessionId())
                .sessionStart(session.getFirstEventTime())
                .sessionEnd(session.getLastEventTime())
                .lastUpdated(Instant.now())
                .durationSeconds((Long) metrics.getOrDefault("durationSeconds", 0L))
                .totalEvents(session.getTotalEvents())
                .totalLines(session.getTotalLines())
                .filesModified(session.getFilesModified())
                .uniqueFilesCount(session.getFilesModified().size())
                .linesPerMinute((Double) metrics.get("linesPerMinute"))
                .eventsPerMinute((Double) metrics.get("eventsPerMinute"))
                .averageTimeBetweenEvents((Double) metrics.get("averageTimeBetweenEvents"))
                .linesPerFile(session.getLinesPerFile())
                .mostEditedFile((String) metrics.get("mostEditedFile"))
                .mostEditedFileLines((Integer) metrics.get("mostEditedFileLines"))
                .eventsBySource(session.getEventsBySource())
                .build();
    }

    /**
     * Merge new analytics with existing (for long-running sessions)
     *
     * Design Decision: Incremental updates instead of replace
     * Why? Sessions might span multiple flush cycles
     */
    private void mergeAnalytics(SessionAnalytics existing, SessionAnalytics newData) {
        existing.setSessionEnd(newData.getSessionEnd());
        existing.setLastUpdated(Instant.now());
        existing.setTotalEvents(existing.getTotalEvents() + newData.getTotalEvents());
        existing.setTotalLines(existing.getTotalLines() + newData.getTotalLines());

        // Merge sets
        existing.getFilesModified().addAll(newData.getFilesModified());
        existing.setUniqueFilesCount(existing.getFilesModified().size());

        // Merge maps
        newData.getLinesPerFile().forEach((file, count) ->
                existing.getLinesPerFile().merge(file, count, Integer::sum)
        );

        newData.getEventsBySource().forEach((source, count) ->
                existing.getEventsBySource().merge(source, count, Integer::sum)
        );

        // Recalculate duration and rates
        if (existing.getSessionStart() != null && existing.getSessionEnd() != null) {
            long duration = existing.getSessionEnd().getEpochSecond() -
                    existing.getSessionStart().getEpochSecond();
            existing.setDurationSeconds(Math.max(1, duration));

            double minutes = duration / 60.0;
            if (minutes > 0) {
                existing.setLinesPerMinute(existing.getTotalLines() / minutes);
                existing.setEventsPerMinute(existing.getTotalEvents() / minutes);
            }
        }

        // Update most edited file
        existing.getLinesPerFile().entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .ifPresent(entry -> {
                    existing.setMostEditedFile(entry.getKey());
                    existing.setMostEditedFileLines(entry.getValue());
                });
    }
}