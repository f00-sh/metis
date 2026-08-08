# TODO — Use symbols, not regurgitate

**Plan (full):** [docs/plans/2026-04-use-symbols-not-regurgitate.md](../docs/plans/2026-04-use-symbols-not-regurgitate.md)  
**Status:** APPROVED + implemented (P0–P6); P7 polish deferred  

## Approval

- [x] Read full plan
- [x] Choose: equality form `(= a b)` (recommended)
- [x] Choose: single-turn multi-clause in Phase 3 (recommended)
- [x] Choose: post-Phase-6 version bump 4.6 USE (recommended) — deferred to release workflow
- [x] Sign approval block in the plan file

## After approval (execute in order)

- [x] **P0** Contract + `:metis-reason-act` tests (x=y / what is y)
- [x] **P1** Act parser + assert → mind facts
- [x] **P2** Query prove/bind chase (y=x; value chase)
- [x] **P3** Process composition + multi-clause demo sentence
- [x] **P4** Equality graph + prove-query path (minimal rule marker; chase primary)
- [x] **P5** Freeform reorder; knowledge-about only for about-Qs; extractive regression
- [x] **P6** Learn-on-success only (hippocampus episode)
- [ ] **P7** Bindings visibility + CHANGELOG/release when shipping

## Definition of done (paste check)

```
> x = y          → asserted
> what is y      → y = x  (source prove/bind, not math-knowledge dump)
> x = 2
> what is y      → 2  (multi supporters)
> what is a limit? → knowledge about (not bindings)
> tell me about penguins (doc) → extractive still works
```

If solve/query answers with “From loaded math symbols: • …”, **not done**.
