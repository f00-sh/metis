# Changelog

## 4.0.1 — multi-layer LM, attachment continuous train, TMS neural gate

### Language model
- Multi-layer depth (`:depth`, default 2) with stack of Linear+ReLU hidden layers
- Causal context window (`:seq-len`) used end-to-end via `t-causal-context-mean` in train and generate
- Train history/meta records `depth`, `seq-len`, `hidden`

### Corpus pipeline
- `session-corpus` assembles text from session file + context attachments
- `nn-continuous-train` continues a named registered model without process restart
- `nn-train-from-session` = attachments → continuous train
- iface: `/train attachments [name]`

### TMS-gated neural fire
- Policy fact `nn-path-enabled` must be TMS IN for generate
- `nn-enable-path` / `nn-disable-path` / `nn-path-allowed-p` / `nn-check-path!`
- `nn-generate` is the choke point — OUT refuses with `metis-error` (no silent sample)
- Boot enables path by default; `/nn enable` `/nn disable` in iface

### Tests
- `:metis-nn` covers deeper/wider LM, attachment continuous train, TMS gate IN/OUT

## 4.0.0 — NEURAL (in-process trainable models + symbolic control)

### Core capability
- **Pure Common Lisp neural substrate** (`metis.nn`): dense tensors, reverse-mode autograd, linear/embedding/MLP, Adam/SGD, character language models, checkpoint I/O, model registry
- **No Python / no external ML runtime required** for train or generate
- **Mind bridge**: train/infer tools installed at boot; KB/TMS facts for model readiness; iface `/train`, `/generate`, `/nn list`
- Symbolic stack (unifier, RETE, TMS, planner, EPOCH, INTERFACE) remains first-class control — neural and symbolic share one process

### Modules
- `src/nn/tensor.lisp` — tensor + reverse-mode AD
- `src/nn/ops.lisp` — matmul, activations, losses, embedding
- `src/nn/module.lisp` — layers + optimizers
- `src/nn/train.lisp` — vocab, LM, train loops, checkpoints, registry
- `src/nn/bridge.lisp` — product integration

### API
- `nn-train-language-model`, `nn-train-file`, `nn-generate`, `nn-train-mlp-xor`, `install-nn-tools`
- Defaults sized for real corpora (`hidden` 256, `seq-len` 64); checkpoints under `models/`

### Tests
- Suite `:metis-nn` — autograd, XOR, LM train/generate, checkpoint, tools-on-boot
- Full battery green: core · production · bench · further · epoch · iface · nn

## 3.1.0 — INTERFACE (full interactive product surface)

### Interactive multi-turn interface
- `session` + `iface` modules: multi-turn session without process restart
- Attachments: **files** (text extract), **context** strings, **photos** (path/type/size/caption)
- `/need CAP` self-accommodation via TMS-guarded self-mod + tool/skill registration
- Launchers: `./bin/iface`, `./bin/metis iface` (`--demo`, `--drive`, REPL)
- HTTP: `POST /v1/session`, `/v1/session/turn`, `/v1/session/attach`
- Suite `:metis-iface`

## 3.0.0 — EPOCH (Enduring Process of Open Cognitive Homotopy)

### Flagship program
- `bin/epoch` / `metis epoch` — primary post-ARC program entry
- Multi-session open-goal pursuit with durable suspend/resume across process restarts
- Live introspective ingest of the mind's own code surface as cognitive material
- TMS-guarded self-modification of rules/skills with rollback on integrity failure

### Leap past 2.0 ARC
- ARC = single-session continuum cycle
- EPOCH = multi-session open pursuit + code-as-cognition + guarded self-mod as one unit

### Tests
- Suite `:metis-epoch` — flagship, leap resume, self-mod, self-code ingest

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
