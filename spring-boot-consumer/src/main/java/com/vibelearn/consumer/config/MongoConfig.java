package com.vibelearn.consumer.config;

import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.mongodb.core.MongoTemplate;

@Configuration
public class MongoConfig {

    private final String mongoUri;
    private final String databaseName;

    public MongoConfig(
        @Value("${spring.data.mongodb.uri:mongodb://localhost:27017/vibe_learn}") String mongoUri,
        @Value("${spring.data.mongodb.database:vibe_learn}") String databaseName) {
            this.mongoUri = mongoUri;
            this.databaseName = databaseName;
    }

    @Bean
    public MongoClient mongoClient() {
        return MongoClients.create(mongoUri);
    }

    @Bean
    public MongoTemplate mongoTemplate() {
        return new MongoTemplate(mongoClient(), databaseName);
    }
}