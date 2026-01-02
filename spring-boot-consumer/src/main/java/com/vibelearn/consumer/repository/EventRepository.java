package com.vibelearn.consumer.repository;

import com.vibelearn.consumer.model.CodeEvent;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * MongoDB repository for CodeEvent documents.
 * Spring Data automatically implements basic CRUD operations.
 */
@Repository
public interface EventRepository extends MongoRepository<CodeEvent, String> {
    
    // Custom query methods (Spring generates implementation automatically!)
    
    /**
     * Find all events for a specific session.
     * Method name convention: findBy + FieldName
     */
    List<CodeEvent> findBySessionId(String sessionId);
    
    /**
     * Find events by session and file.
     */
    List<CodeEvent> findBySessionIdAndFileUri(String sessionId, String fileUri);
    
    /**
     * Count events in a session.
     */
    long countBySessionId(String sessionId);
}