package com.vibelearn.analytics.repository;

import com.vibelearn.analytics.model.SessionAnalytics;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

@Repository
public interface SessionAnalyticsRepository extends MongoRepository<SessionAnalytics, String> {

    /**
     * Find analytics by session ID (most common query)
     */
    Optional<SessionAnalytics> findBySessionId(String sessionId);

    /**
     * Find sessions updated after a certain time (for incremental processing)
     */
    List<SessionAnalytics> findByLastUpdatedAfter(Instant timestamp);

    /**
     * Find top N sessions by events (for leaderboard)
     */
    @Query(value = "{}", sort = "{ 'totalEvents': -1 }")
    List<SessionAnalytics> findTopByTotalEvents();

    /**
     * Find sessions with high activity (>50 lines/min)
     */
    List<SessionAnalytics> findByLinesPerMinuteGreaterThan(Double threshold);
}