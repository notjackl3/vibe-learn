package com.vibelearn.ingest.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class CodeEvent {
    
    @NotBlank(message = "Session ID is required")
    private String sessionId;
    
    @NotNull(message = "Client timestamp is required")
    private Long clientTimestampMs;  // Changed from long to Long
    
    @NotBlank(message = "File URI is required")
    private String fileUri;
    
    @NotBlank(message = "File name is required")
    private String fileName;
    
    @NotNull(message = "Line number is required")
    private Integer lineNumber;  // Changed from int to Integer
    
    @NotBlank(message = "Text normalized is required")
    private String textNormalized;
    
    @NotBlank(message = "Source is required")
    private String source;

    private Long serverTimestampMs;
}