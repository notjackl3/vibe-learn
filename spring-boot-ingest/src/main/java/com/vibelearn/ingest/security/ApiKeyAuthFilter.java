package com.vibelearn.ingest.security;

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

/**
 * Filter that validates API key from X-API-Key header.
 * Runs on every request to protected endpoints.
 */
@Component  // Spring manages this as a bean
@Slf4j
public class ApiKeyAuthFilter extends OncePerRequestFilter {

    private static final String API_KEY_HEADER = "X-API-Key";
    
    @Value("${API_KEY:custom-api-key-here}")
    private String validApiKey;  // The correct API key from application.yml

    // Prevent API key requirements for Grafana and Prometheus services
    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        return path.startsWith("/actuator/") || !path.startsWith("/api/");
    }


    /**
     * Checks every request for valid API key.
     * If valid, allows request to proceed. If invalid, returns 401.
     */
    @Override
    protected void doFilterInternal(HttpServletRequest request, 
                                    HttpServletResponse response, 
                                    FilterChain filterChain) 
            throws ServletException, IOException {
        
        // Extract API key from request header
        String providedApiKey = request.getHeader(API_KEY_HEADER);
        
        // Check if API key matches
        if (providedApiKey != null && providedApiKey.equals(validApiKey)) {
            // Valid! Set authentication in Spring Security context
            // (tells Spring: this request is authenticated)
            UsernamePasswordAuthenticationToken auth = 
                new UsernamePasswordAuthenticationToken("api-user", null, Collections.emptyList());
            SecurityContextHolder.getContext().setAuthentication(auth);
            
            log.debug("Valid API key provided from IP: {}", request.getRemoteAddr());
            
            // Continue to next filter/controller
            filterChain.doFilter(request, response);
            
        } else {
            // Invalid or missing API key
            log.warn("Invalid or missing API key from IP: {}", request.getRemoteAddr());
            
            // Return 401 Unauthorized
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json");
            response.getWriter().write("{\"error\": \"Invalid or missing API key\"}");
        }
    }
}