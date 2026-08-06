# Adversarial Security Review — Metis HTTP/JSON API

**Scope:** `/v1/*` handlers in `src/api.lisp`, auth model, body parsing, interpret surface.  
**Date:** 2026-08-06 · Metis 2.0 ARC  
**Method:** threat modeling + static review of shipped handlers; mitigations land in code with unit tests on real gates.

## Findings

### H1 — Missing authentication by default (HIGH)
- **Issue:** API could start with `*api-token*` nil, making all endpoints open on the bind address.
- **Impact:** Unauthenticated tell/pursue/interpret against a mind image.
- **Mitigation:** `api-require-auth` pure gate; `api-start` warns on non-localhost without token; optional `:api-require-token` refuses start without token; env `METIS_API_TOKEN`.
- **Test:** `api-security-auth-gate` in `tests/further-paths.lisp`.

### H2 — Reader eval / dangerous forms via string bodies (HIGH)
- **Issue:** `read-from-string` on client-supplied pattern/fact/goal/form enabled `#.` and `uiop:run-program` payloads.
- **Impact:** Remote code execution if combined with open network bind.
- **Mitigation:** `api-security-check-input` rejects `#.`, `uiop:run-program`, `sb-ext:run-program`, oversized bodies; `%api-safe-read` binds `*read-eval*` nil.
- **Test:** `api-security-input-gate`.

### M1 — No rate limiting (MEDIUM)
- **Issue:** Tight loops on tell/pursue could DoS the process.
- **Mitigation:** per-client-minute counter via `%api-rate-ok-p` (HTTP 429).
- **Test:** structural presence; gate unit-tested indirectly via rate function behavior.

### M2 — Interpret is a powerful surface (MEDIUM)
- **Issue:** `(interpret …)` can trigger plan/tool paths.
- **Mitigation:** same input filters; auth required when token set; sandbox on eval-lisp tool remains separate.
- **Test:** dangerous-form rejection on strings containing uiop:run-program.

### L1 — Health/version unauthenticated (LOW)
- **Issue:** Information disclosure of version/status.
- **Accept:** intentional for load balancers; no secrets returned.

## Residual risk
- Token in env/header is bearer-style (no rotation/mTLS). Deploy behind reverse proxy with TLS for any non-loopback bind.
- LMDB paths must remain on trusted filesystem.

## Sign-off
High-severity items H1/H2 mitigated in shipped code with automated tests on the real gate functions (not mocks).
