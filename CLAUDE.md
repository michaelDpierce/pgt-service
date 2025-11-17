# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PGT Service is a Rails 8.0 API-only application that integrates with Hume AI for emotional analysis of meeting transcripts and uses OpenAI to generate structured summaries. The service uses Clerk for authentication and PostgreSQL for data persistence.

## Key Commands

### Development Server
```bash
bin/dev                    # Start development server (Passenger on port 3001)
bundle exec passenger start --port 3001 --environment development
```

### Database
```bash
bin/rails db:create        # Create database
bin/rails db:migrate       # Run migrations
bin/rails db:reset         # Drop, create, migrate, and seed
bin/rails db:schema:load   # Load schema from schema.rb (faster than migrations)
```

### Testing & Quality
```bash
bin/rails test             # Run all tests
bin/rails test test/controllers/meetings_controller_test.rb  # Run single test file
bin/brakeman              # Security scanner
bin/rubocop               # Linter (omakase style)
bin/rubocop -a            # Auto-fix linter issues
```

### Console & Utilities
```bash
bin/rails console         # Open Rails console
bin/rails routes          # List all routes
```

## Architecture

### Authentication Flow
All API requests (except `/up` health check) require Clerk JWT authentication via `ApplicationController#authenticate_with_clerk!`. The Bearer token is verified using the Clerk SDK, and user records are upserted on each request with claims from the JWT (clerk_id, email, name, avatar_url). The `@current_user` is set for use throughout the request lifecycle.

### Core Data Models

**User** (uuid primary key)
- Identified by `clerk_id` (unique, from Clerk auth)
- Has many meetings (nullified on user deletion)
- Auto-synced on each authenticated request

**Meeting** (uuid primary key)
- Belongs to User
- Optionally belongs to HumeSession (via `hume_session_id` foreign key)
- Required fields: `title`, `hume_label`, `hume_config`
- Supports full-text search on title (ILIKE)
- Indexed by title and user_id

**HumeSession** (bigint primary key)
- Stores raw Hume webhook data + OpenAI-generated summary in `data` JSONB column
- Has one Meeting
- Contains transcript, emotion analysis, and structured summary

### Hume AI Integration

The service integrates with Hume AI's emotion analysis platform through three main flows:

1. **Token Generation** (`HumeTokensController#create`)
   - Exchanges HUME_API_KEY + HUME_SECRET_KEY for OAuth2 access token
   - Returns token to client for Hume SDK initialization

2. **Session Creation** (`HumeSessionsController#create`)
   - Receives transcript payload with emotion data from client
   - Creates HumeSession record with raw data
   - Sends transcript to OpenAI (gpt-4.1-mini) for structured analysis
   - Uses JSON schema enforcement with fallbacks for strict parsing
   - Updates HumeSession with summary and links to Meeting

3. **Webhook Verification** (`HumeSignatureVerifiable` concern)
   - Verifies Hume webhook signatures using HMAC-SHA256
   - Compares `X-Hume-AI-Webhook-Signature` header against computed hash
   - Uses `X-Hume-AI-Webhook-Timestamp` as part of signature payload

### OpenAI Summary Structure

The `HumeSessionsController` generates structured summaries with these buckets:
- **best_personal/worst_personal/impact_personal**: Personal life highlights, challenges, impacts
- **best_work/worst_work/impact_work**: Work-related items
- **best_family/worst_family/impact_family**: Family-related items
- **emotions_summary**: Top 3 user emotions with mean scores and occurrences
- **overall_session_summary**: 3-6 sentence narrative of the session

The prompt computes emotion statistics from transcript data (either `emotions_all` hash or `emotions_top3` array) and uses JSON schema strict mode with two fallback strategies if parsing fails.

### API Endpoints

All routes default to JSON format:

- `GET /`: Welcome endpoint (unauthenticated root)
- `GET /up`: Health check (unauthenticated)
- `POST /hume/token`: Generate Hume OAuth token
- `POST /hume/sessions`: Process session and create summary
- `POST /webhooks/hume`: Receive Hume webhooks (signature verified)
- `GET /meetings`: List meetings (with search, sort, pagination via Pagy)
- `POST /meetings`: Create meeting
- `GET /meetings/:id`: Show meeting with associated HumeSession
- `DELETE /meetings/:id`: Destroy meeting and associated HumeSession (transactional)

### CORS Configuration

CORS is configured to allow:
- Origins: `http://localhost:3001` and `ENV["FRONTEND_ORIGIN"]` (falls back to `*`)
- Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD
- Exposed headers: Authorization

## Environment Variables

Required variables (set in `.env.local` for development):

```
HUME_API_KEY          # Hume AI API key
HUME_SECRET_KEY       # Hume AI secret key
CLERK_SECRET_KEY      # Clerk backend API key
CLERK_PUBLISHABLE_KEY # Clerk frontend key
OPENAI_ACCESS_TOKEN   # OpenAI API key
FRONTEND_ORIGIN       # CORS origin (e.g., http://localhost:3000)
```

## Database Notes

- PostgreSQL with UUID primary keys for users and meetings
- JSONB column for HumeSession data storage (efficient querying with GIN indexes available)
- Uses `gen_random_uuid()` for UUID generation
- All timestamps are managed by Rails (created_at, updated_at)

## Dependencies

Key gems:
- **clerk-sdk-ruby**: Clerk authentication
- **ruby-openai**: OpenAI API client
- **pagy**: Pagination (backend only, returns metadata for frontend)
- **rack-cors**: CORS middleware
- **passenger**: Application server (development and production)
- **solid_cache**: Rails caching backend
