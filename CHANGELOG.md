# Changelog

## 2.0.0 — ARC (Autopoietic Reflexive Continuum)

### Novel intelligence thesis
- **ARC**: dual-pathway continuum uniting RETE reactive cortex, TMS-verified deliberation, and durable LMDB continuum memory with autopoietic repair cycles (`src/arc.lisp`).

### Further paths
- RETE-compiled forward inference (`src/rete.lisp`, `forward-chain-rete`)
- LMDB durable store + mind save/load round-trip (`src/durable.lisp`)
- Formal TMS property suite P1–P6 (`src/tms-formal.lisp`)
- Large taxonomy/graph corpus (`knowledge/large-corpus.lisp`)
- Adversarial API review + auth/input/rate mitigations (`docs/adversarial-api-review.md`, `src/api.lisp`)

### Tests
- Suite `:metis-further` gates all acceptance paths

## 1.0.0 — Full-Bore (production)

### Architecture
- Justification-based TMS (JTMS-lite) with why-explanations
- HTN hierarchical planner integrated with STRIPS operators
- Weighted belief store + decay
- Finite-domain CSP solver
- Multi-agent society + blackboard + messaging
- Transactional assert/retract with rollback
- Chunking / skill compilation from successful plans
- Deep explanation engine (`explain-deep`, `why`)

### Production runtime
- Structured logging
- Config file + env (`metis.conf`, `METIS_*`)
- Sandboxed `eval` policy
- HTTP/JSON API (Hunchentoot) `/v1/*`
- Background cognitive daemon
- `production-boot` ensemble launcher
- Domain packs: blocks HTN, kinship, digital circuits, CSP demo

### Quality
- Expanded FiveAM suites: core, production, bench
- GitHub Actions CI (SBCL + Quicklisp)
- Semantic version 1.0.0

## 0.1.0 — Initial cognitive kernel

- Unifier, KB, frames, forward/backward chaining
- STRIPS planner, memory systems, meta-control
- Tools, optional LLM bridge, REPL, world save/load
