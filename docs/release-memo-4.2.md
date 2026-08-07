# Release memo — Metis 4.2.0 FRONTIERS

**Product:** Metis  
**Version:** 4.2.0  
**Codename:** FRONTIERS  
**Date:** 2026-08-07  

## Summary

This line delivers the five frontiers called out after Metis 4.1 SYMBOLS:

1. **More symbols** — `chat-ui`, `image-ingest`, `domain-pack`, `curriculum` (list/enable; real tools & content).
2. **Richer GPU path** — on-device **axpy** and **relu** in addition to SGEMM; numeric agreement with CPU; clean fail without CUDA.
3. **Remote install + trust** — git/HTTP(S)/`file://` install with HMAC `symbol.sig` verification; unsigned remote refused.
4. **Longer/deeper LM + GPU train** — product defaults depth **3**, seq-len **128**; train history records active backend and op counts so GPU-backed loops are evidence, not decoration.
5. **Product packaging** — `./bin/package-metis` builds a runnable SBCL core image; docs triad (`docs/overview.md`, `docs/install.md`, `docs/develop.md`); this release memo.

## Non-goals restated

Not GPT-scale; not GPU-default; not Python train; not a public app-store PKI.

## Verification

`./bin/metis test` must remain green across core · production · bench · further · epoch · iface · nn · symbols · frontiers.

## Operators

See `docs/install.md`. Developers: `docs/develop.md`. Overview: `docs/overview.md`.
