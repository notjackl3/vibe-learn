package com.vibelearn.ingest.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

// This is just a data container for the JSON coming in from the VS Code extension
@Data
@AllArgsConstructor
@NoArgsConstructor
public class CodeEvent {
    @NotBlank(message = "Session ID is required")
    private String sessionId;
    @NotNull(message = "Client timestamp is required")
    private long clientTimestampMs;
    @NotBlank(message = "File URI is required")
    private String fileUri;
    @NotBlank(message = "File name is required")
    private String fileName;
    @NotNull(message = "Line number is required")
    private int lineNumber;
    @NotBlank(message = "Text normalized is required")
    private String textNormalized;
    @NotBlank(message = "Source is required")
    private String source;

    private Long serverTimestampMs;
}
