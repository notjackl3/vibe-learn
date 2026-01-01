package com.vibelearn.ingest.config;

import com.vibelearn.ingest.security.ApiKeyAuthFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Configures security for the ingest API.
 * Requires API key authentication for /api/events endpoint.
 */
@Configuration
@EnableWebSecurity  // Enables Spring Security
@RequiredArgsConstructor
public class SecurityConfig {

    private final ApiKeyAuthFilter apiKeyAuthFilter;

    /**
     * Configures the security filter chain.
     * This defines which endpoints require authentication and how.
     */
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            // Disable CSRF (not needed for API-only service with API key auth)
            .csrf(csrf -> csrf.disable())
            
            // No sessions - each request must have API key (stateless)
            .sessionManagement(session -> 
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            
            // Authorization rules
            .authorizeHttpRequests(auth -> auth
                // Require authentication for /api/** endpoints
                .requestMatchers("/api/**").authenticated()
                // Allow health checks, metrics without auth (for monitoring)
                .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                // Deny everything else by default
                .anyRequest().denyAll()
            )
            
            // Add our custom API key filter BEFORE Spring's username/password filter
            .addFilterBefore(apiKeyAuthFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}