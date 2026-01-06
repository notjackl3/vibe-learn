package com.vibelearn.ingest.security;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Collections;

@Component
@Slf4j
public class ApiKeyAuthFilter extends OncePerRequestFilter {

    private static final String API_KEY_HEADER = "X-API-Key";

    private final String validApiKey;

    // ⭐ Metrics
    private final Counter requestsReceived;
    private final Counter requestsAuthenticated;
    private final Counter requestsRejected;
    private final Timer requestTimer;

    public ApiKeyAuthFilter(
            @Value("${api.key:custom-api-key-here}") String validApiKey,
            MeterRegistry meterRegistry) {

        this.validApiKey = validApiKey;

        log.info("ApiKeyAuthFilter initialized with API key: {}...",
                validApiKey.substring(0, Math.min(10, validApiKey.length())));

        // ⭐ Initialize metrics
        this.requestsReceived = Counter.builder("ingest_api_requests_total")
                .description("Total API requests received")
                .tag("service", "ingest")
                .register(meterRegistry);

        this.requestsAuthenticated = Counter.builder("ingest_api_authenticated_total")
                .description("Successfully authenticated requests")
                .tag("service", "ingest")
                .register(meterRegistry);

        this.requestsRejected = Counter.builder("ingest_api_rejected_total")
                .description("Rejected requests (invalid API key)")
                .tag("service", "ingest")
                .register(meterRegistry);

        this.requestTimer = Timer.builder("ingest_api_request_duration_seconds")
                .description("API request processing time")
                .tag("service", "ingest")
                .register(meterRegistry);
    }

    /**
     * Skip filtering for actuator endpoints - they should be public
     */
    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        boolean skip = path.startsWith("/actuator/");

        if (skip) {
            log.debug("Skipping API key check for: {}", path);
        }

        return skip;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        String requestURI = request.getRequestURI();

        log.debug("API key filter checking: {} {}", request.getMethod(), requestURI);

        // ⭐ Count the request
        requestsReceived.increment();

        // ⭐ Time the request
        Timer.Sample sample = Timer.start();

        try {
            String providedApiKey = request.getHeader(API_KEY_HEADER);

            if (providedApiKey == null) {
                log.warn("Missing API key for: {} from IP: {}",
                        requestURI, request.getRemoteAddr());
                requestsRejected.increment();
                sendUnauthorized(response, "Missing API key");
                return;
            }

            if (!providedApiKey.equals(validApiKey)) {
                log.warn("Invalid API key for: {} from IP: {}",
                        requestURI, request.getRemoteAddr());
                requestsRejected.increment();
                sendUnauthorized(response, "Invalid API key");
                return;
            }

            // ⭐ Valid API key!
            log.debug("Valid API key for: {}", requestURI);
            requestsAuthenticated.increment();

            // Set authentication in Spring Security context
            UsernamePasswordAuthenticationToken auth =
                    new UsernamePasswordAuthenticationToken(
                            "api-user", null, Collections.emptyList()
                    );
            SecurityContextHolder.getContext().setAuthentication(auth);

            // Continue to next filter/controller
            filterChain.doFilter(request, response);

        } finally {
            // ⭐ Record request duration
            sample.stop(requestTimer);
        }
    }

    private void sendUnauthorized(HttpServletResponse response, String message)
            throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json");
        response.getWriter().write(
                "{\"error\": \"" + message + "\", \"hint\": \"Include X-API-Key header\"}"
        );
    }
}