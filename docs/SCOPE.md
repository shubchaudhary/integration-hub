# Scope

## Problem
(2-3 lines: duplicate webhooks, destination downtime, silent failures)

## v1 in scope
- HMAC-verified webhook ingestion
- Idempotent storage (unique source + external id)
- Queued delivery, retries with exponential backoff, DEAD state
- Manual retry, audit log
- JWT auth with roles
- React dashboard

## Out of scope for v1
- Multi-tenancy, multiple destinations, Prometheus

## Success criteria
1. No lost events
2. No duplicate side effects
3. No silent failures