package com.vibelearn.consumer;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.mongodb.repository.config.EnableMongoRepositories;
import org.springframework.boot.mongodb.autoconfigure.MongoAutoConfiguration;;

// Prevents autoconfiguration of MongoDB setting to localhost:27017
@SpringBootApplication(exclude = MongoAutoConfiguration.class)
// Add this line to force Spring to find your repository
@EnableMongoRepositories(basePackages = "com.vibelearn.consumer.repository", mongoTemplateRef = "mongoTemplate")
public class SpringBootConsumerApplication {
    public static void main(String[] args) {
        SpringApplication.run(SpringBootConsumerApplication.class, args);
    }
}