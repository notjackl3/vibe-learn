---
name: Web Quiz + Kafka
overview: Keep the VS Code extension as a recorder that sends events to a Spring Boot ingestion API; the backend produces to Kafka, persists to MongoDB, and exposes a minimal web app to generate on-demand LLM quizzes from recorded sessions.
todos:
  - id: compose-stack
    content: Add docker-compose stack for Kafka + MongoDB + Spring Boot services + web app (dev)
    status: completed
  - id: ingest-api
    content: Implement Spring Boot ingest API (API key auth) and Kafka producer for code events
    status: pending
    dependencies:
      - compose-stack
  - id: persist-consumer
    content: Implement Kafka consumer to persist code events into MongoDB
    status: pending
    dependencies:
      - compose-stack
      - ingest-api
  - id: quiz-api
    content: Implement session CRUD + on-demand quiz generation endpoints; enqueue quiz jobs
    status: pending
    dependencies:
      - compose-stack
      - persist-consumer
  - id: quiz-worker
    content: Implement quiz worker consuming jobs; gather code context; call LLM; store quiz in MongoDB
    status: pending
    dependencies:
      - compose-stack
      - quiz-api
  - id: web-ui
    content: "Implement minimal React UI: create session goal, list sessions, generate quiz, take quiz"
    status: pending
    dependencies:
      - quiz-api
  - id: ext-session-tagging
    content: Update VS Code extension to prompt/select sessionId and POST events to ingest API with API key
    status: pending
    dependencies:
      - ingest-api
  - id: docs-runbook
    content: Document setup, env vars (API keys, LLM), and end-to-end test steps
    status: pending
    dependencies:
      - compose-stack
      - web-ui
      - ext-session-tagging
      - quiz-worker
---

# Web Quiz App + Spring Boot + Kafka + MongoDB (Docker-first)

## Key product flow

- **Before session**: user creates a session in the web app with a goal ("What I want to learn").
- **During session**: VS Code extension sends code-line events tagged with `sessionId`.
- **After session**: user opens the web app and clicks **Generate Quiz**.
- **Generation**: backend gathers relevant code snippets from MongoDB and calls an LLM to create flashcards/quiz items.
- **Review**: web app shows the quiz; user answers; results stored for later progress.

## Services (Docker-first)

- **Kafka**: transport + buffering for events and quiz jobs.
- **MongoDB**: primary storage for sessions, events, quizzes, answers.
- **Spring Boot Ingest API**: `POST /events` (API key auth), produces to Kafka.
- **Spring Boot Persist Consumer**: consumes events and writes to MongoDB.
- **Quiz API**: REST endpoints for session CRUD + quiz generation + quiz retrieval.
- **Quiz Worker**: consumes "generate quiz" jobs, fetches session code context, calls LLM, stores quiz in Mongo.
- **React web app**: minimal UI: create session goal, list sessions, generate quiz, take quiz.

## Data model (MongoDB)

- `sessions`: `{ _id, userId, goalText, createdAt, endedAt }`
- `events`: `{ _id, sessionId, tsClient, tsServer, fileUri, lineNumber, textNormalized, source }`
- `quizzes`: `{ _id, sessionId, createdAt, items:[{prompt, choices?, answer, explanation, codeRefs:[{fileUri,lineNumber}]}] }`
- `answers`: `{ _id, quizId, userId, responses, score, createdAt }`

## Event schema (extension -> backend)

- Required: `sessionId`, `clientTimestampMs`, `fileUri`, `fileName`, `lineNumber`, `textNormalized`, `source`.
- Auth: `X-API-Key`.

## Kafka topics

- `code_events` (from ingest)
- `quiz_generate_requests` (from web/quiz API)
- `quiz_generate_results` (optional; or write directly to Mongo in worker)

## Best-practice choices (why)

- **Extension -> Spring Boot over HTTP** (not direct Kafka): keeps Kafka credentials/server-side, simpler networking.