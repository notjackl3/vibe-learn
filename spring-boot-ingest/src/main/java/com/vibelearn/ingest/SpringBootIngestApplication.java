package com.vibelearn.ingest;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "com.vibelearn")
public class SpringBootIngestApplication {

    public static void main(String[] args) {
        SpringApplication.run(SpringBootIngestApplication.class, args);
    }

}
