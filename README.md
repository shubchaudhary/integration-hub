# Integration Hub

> A webhook-driven data sync platform that receives events from a source system, delivers them reliably to a destination system, and gives operators a dashboard to see what failed and retry it.

<!-- Replace the placeholders below as you build. Delete this comment when done. -->
[![CI](https://github.com/<your-username>/integration-hub/actions/workflows/ci.yml/badge.svg)](https://github.com/<your-username>/integration-hub/actions)

**Live demo:** `<your-deployed-url>` | **Demo video:** `<link>` | **Demo login:** `demo@example.com` / `<password>`

![Dashboard screenshot](docs/screenshots/dashboard.png)

---

## Why this project exists

Enterprise integrations fail in boring, expensive ways: a webhook is delivered twice, a destination API is down for ten minutes, a payload is malformed, and nobody notices until a customer complains.

Integration Hub is a small, production-style answer to that problem. It is built around three guarantees:

1. **No lost events.** Every accepted webhook is stored before it is acknowledged.
2. **No duplicate side effects.** Duplicate deliveries from the source and retries to the destination are both safe (idempotency).
3. **No silent failures.** Every failure is retried with backoff, then surfaced in a dashboard with a manual retry.

<!-- Personalise: add one or two sentences about the real integration work you did at KPMG / Oracle that inspired this. -->

## Features

- Webhook ingestion with **HMAC-SHA256 signature verification**
- **Idempotent** event storage (unique source + external event id)
- Asynchronous delivery through a **Redis-backed job queue (BullMQ)**
- **Retries with exponential backoff**, then a **dead-letter state** for exhausted jobs
- Idempotency key sent to the destination so retries never create duplicates
- Transformation layer that maps source payloads to the destination schema
- JWT authentication with role-based access (admin / member)
- **Audit log** of every state change per event
- Rate limiting on public endpoints
- React dashboard: status counts, success/failure chart, filterable event table, event timeline, one-click retry
- Built-in **chaos mode** on the mock destination to demonstrate failure handling
- Dockerised, tested, CI on every push, deployed with a public URL

## Architecture

```mermaid
flowchart LR
    S[Source system] -->|"POST /webhooks/:source + HMAC"| API[Express API]
    API -->|"insert (idempotent)"| DB[(PostgreSQL)]
    API -->|enqueue| Q[(Redis / BullMQ)]
    Q --> W[Worker]
    W -->|"transform + deliver (Idempotency-Key)"| D[Destination API]
    W -->|"status, attempts, errors"| DB
    W -->|retries exhausted| DEAD[Status: DEAD]
    UI[React dashboard] -->|JWT| API
    API --> DB
```

**Request lifecycle**

1. The source sends a webhook. The API verifies the signature against the raw request body.
2. The API inserts the event. If the (source, external id) pair already exists, it returns `200 duplicate` and stops.
3. The API enqueues a job and responds `202 Accepted` quickly, so the source never waits on the destination.
4. A worker picks up the job, transforms the payload, and calls the destination with an idempotency key.
5. On success the event becomes `DELIVERED`. On failure the job retries with exponential backoff. After the final attempt the event becomes `DEAD` and appears in the dashboard.
6. Every transition writes an audit log entry.

**Event states:** `RECEIVED` > `PROCESSING` > `DELIVERED`, with `FAILED` (will retry) and `DEAD` (retries exhausted) as failure states.

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Runtime | Node.js 20 + TypeScript | Type safety across the codebase |
| API | Express, Zod | Simple, familiar; Zod validates all input |
| Database | PostgreSQL + Prisma | Relational integrity and unique constraints for idempotency |
| Queue | BullMQ on Redis | Retries, backoff and concurrency out of the box |
| Auth | JWT + bcrypt | Stateless auth, hashed passwords |
| Frontend | React + Vite + TypeScript, TanStack Query, Recharts | Fast dev loop, polling and caching handled |
| Testing | Vitest, Supertest | Unit and integration tests |
| DevOps | Docker Compose, GitHub Actions | Reproducible local setup and CI |
| Load testing | k6 | Scriptable, signs requests with HMAC |

## Getting started

### Prerequisites

- Node.js 20+
- Docker and Docker Compose

### Run locally

```bash
# 1. Clone
git clone https://github.com/<your-username>/integration-hub.git
cd integration-hub

# 2. Start Postgres and Redis
docker compose up -d

# 3. Configure the server
cd server
cp .env.example .env        # then edit the secrets
npm install
npx prisma migrate dev
npm run seed                # creates the demo admin user

# 4. Start the API and the worker (two terminals)
npm run dev
npm run worker

# 5. Start the dashboard (third terminal)
cd ../client
npm install
npm run dev
```

Open `http://localhost:5173` and sign in with the seeded demo user.

### Environment variables

| Variable | Example | Purpose |
|---|---|---|
| `DATABASE_URL` | `postgresql://hub:hub@localhost:5432/hub` | PostgreSQL connection |
| `REDIS_URL` | `redis://localhost:6379` | Queue connection |
| `JWT_SECRET` | long random string | Signs access tokens |
| `WEBHOOK_SECRET` | long random string | Verifies incoming webhook signatures |
| `TOKEN_ENC_KEY` | 64 hex characters | Encrypts stored OAuth tokens (AES-256-GCM) |
| `DESTINATION_URL` | `http://localhost:4000/mock-erp/orders` | Where events are delivered |
| `CHAOS_FAILURE_RATE` | `0.3` | Fraction of mock destination calls that fail |

## Try it: send a signed webhook

```bash
BODY='{"id":"evt_1001","type":"order.created","total":499,"currency":"INR"}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/^.* //')

curl -X POST http://localhost:4000/webhooks/shop \
  -H "Content-Type: application/json" \
  -H "x-signature: $SIG" \
  -d "$BODY"
```

Send the same command twice: the second response is `200 {"duplicate":true}` and no second delivery happens.

## API reference

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/webhooks/:source` | HMAC signature | Receive an event |
| POST | `/auth/register` | none | Create a user |
| POST | `/auth/login` | none | Get a JWT |
| GET | `/events` | JWT | List events (`status`, `page`, `limit` filters) |
| GET | `/events/:id` | JWT | Event detail with audit timeline |
| POST | `/events/:id/retry` | JWT (admin) | Re-enqueue a failed or dead event |
| GET | `/stats` | JWT | Counts by status and recent success rate |
| GET | `/connections` | JWT | List connected third-party accounts |
| GET | `/connections/:provider/start` | JWT | Begin the OAuth flow |
| GET | `/connections/:provider/callback` | state param | Complete the OAuth flow |
| GET | `/health` | none | Liveness and dependency check |

## Design decisions and trade-offs

| Decision | Reason | Trade-off |
|---|---|---|
| At-least-once delivery plus idempotency keys | Exactly-once is not achievable across systems; this gives the same observable result | Destination must honour the idempotency key |
| Store the event before enqueueing | A crash after acknowledging cannot lose data | Small window where an event is stored but not queued; a sweeper job re-enqueues events stuck in `RECEIVED` |
| Respond `202` before delivery | Source is never blocked by a slow destination | Delivery result is asynchronous, so the dashboard is needed |
| Unique constraint in the database for dedupe | Correct under concurrent requests, unlike check-then-insert | Relies on database error handling |
| Verify HMAC on the raw body | Re-serialised JSON can differ from what was signed | Webhook route must be mounted before the JSON body parser |
| Permanent errors (4xx) are not retried | Retrying a bad payload only wastes capacity | Needs correct classification of errors |

## How it would scale 10x

- Run multiple stateless API instances behind a load balancer.
- Scale workers horizontally; BullMQ distributes jobs across them.
- Add database indexes on `(status, createdAt)` and partition or archive old events.
- Move rate limiting to a Redis-backed store shared across instances.
- Add an outbox table plus a dedicated publisher to close the store-then-enqueue gap completely.
- Add per-destination concurrency limits and circuit breakers so one failing destination does not starve others.

## Testing

```bash
cd server
npm test
```

Covered: signature verification (valid, invalid, missing), idempotent duplicate handling, retry and dead-letter transitions, transformation mapping, auth and role checks.

## Performance

<!-- Fill in after running the k6 script in docs/load-test.js. -->
| Metric | Result |
|---|---|
| Test setup | `<e.g. 50 virtual users, 30 s, 1 API instance, 1 worker>` |
| Webhook ingestion throughput | `<requests/sec>` |
| p95 response time | `<ms>` |
| Error rate | `<%>` |

## Project structure

```
integration-hub/
├── docker-compose.yml
├── docs/
│   ├── screenshots/
│   └── load-test.js
├── server/
│   ├── prisma/schema.prisma
│   └── src/
│       ├── app.ts              # Express app setup
│       ├── index.ts            # API entry point
│       ├── worker.ts           # Queue worker entry point
│       ├── config/             # env validation
│       ├── middleware/         # auth, rate limit, errors
│       ├── routes/             # auth, events, webhooks, connections, mock-erp
│       ├── services/           # transform, deliver, audit, crypto
│       ├── queue/              # queue and sweeper
│       └── tests/
├── client/
│   └── src/                    # pages, components, API hooks
└── .github/workflows/ci.yml
```

## Roadmap

- [ ] Outbox pattern instead of the sweeper
- [ ] Multiple destinations per source with routing rules
- [ ] Replay a date range of events
- [ ] Prometheus metrics and Grafana dashboard
- [ ] Per-tenant API keys and multi-tenancy

## License

MIT
