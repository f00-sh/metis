# Changelog
## 4.4.0 — THEORY + sealed symbols

**Sealed knowledge symbols (game-changer layer):**
- Source kits → `symbol train` → **open-sealed** / **private-sealed** packages (`header.lisp` + opaque `body.mse` + `symbol.sig`)
- Verify hash/HMAC; refuse load on tamper; private-sealed key-gated decrypt
- Free marketplace index (`knowledge/marketplace/index.lisp`) + hash/version advisories
- CLI: `./bin/metis symbol {new,ingest,train,build,verify,load,marketplace-check}`
- Author guide: `docs/SYMBOL-TRAINING.md` · doctrine: `docs/SYMBOL-DOCTRINE.md`
- Five domain symbols trained from open educational citations: **math, algebra, geometry, trigonometry, calculus**
- Tests: `:metis-seals` (62 checks) wired into `./bin/metis test`

## 4.4.0 — THEORY (whitepaper CLS v2) — shipped CLS contract

**Product TUI (pure Common Lisp — no Rust):**
- `./bin/metis tui` (default on TTY): 2-column ANSI/Unicode UI — chat | status + REPL
- Animated METIS splash, color borders, Tab focus, brain/files status pane
- `metis:tui-run` / `metis:tui-splash`

**Background brain (product train, not context-only):**
- `@PATH` / `/attach PATH` / `/context` → extract + **hard** `nn-continuous-train` on async brain queue
- `/watch folder PATH` — continuous poll (~0.35s); new drops train immediately (no manual poll required)
- `/brain status|start|stop` — concurrent learner while user chats; idle corpus consolidation
- Hard defaults: 6 epochs / 64 batches (chat); ingest/watch intensity separate; tests: `:metis-iface`

**Shipped CLS contract (stabilize):**
1. Prioritized interleaved replay (*k*-old+1-new) + **fair** forget-test (identical hyperparams; only replay on/off)
2. Explicit `:replay nil` force-off on `neocortex-consolidate!` (default sentinel `:default`)
3. Episode separation keys + constrained completion
4. Meta-cog metrics + self-model adjust
5. Structured explain object (`supporters`, `tms-label`, `episodes-used`, `weights-stepped`)
6. Coupled neural→symbolic: path-IN `:coupled-reject` via unifier templates (not assert-fact gate)
7. **#7 non-goals remain closed**: no product VAE + Modern Hopfield + CIFAR-100 stack; pure-CL default (Decision B)
8. Suite `:metis-hybrid`

**Session hardenin (product):**
- Default `iface-turn` and `epoch-cognitive-step` always return `:explain` + `:metrics`
- `durable-save-hybrid!` / `durable-load-hybrid!` round-trip hippocampus + hybrid metrics/self-model
- Pure-CL train caps (`*train-max-batches-cap*`, `*train-max-epochs-cap*`)

**Domain depth:**
- `symbols/domain-kinship` pack with couple-templates + rules
- `curriculum-ladder-run` — A→B retention + refuse/allow/learn
- Trust policy: `trust-policy-allows-p`, `nn-enable-path-policy`, `hybrid-teach-policy`

**Marketplace (same repo, not separate product):**
- In-tree catalog + `/marketplace list|install` iface
- Signed packages required for marketplace install path
- External sample: `samples/external-echo/` (signed)

**Research slices (still no #7):**
- Separation probe with fixed cue + retention threshold (`:pass`)
- `hybrid-offline-schedule!` first-class sleep/EPOCH offline mode
- `hybrid-plan-explain` multi-supporter STRIPS/HTN/TMS explain

**Paper-fidelity product slices (without #7):**
- Soft latent replay: episode `:summary` / `:key` text (not VAE vectors) consumed by interleaved batches
- `hybrid-separation-probe`: A→B then goal-A cue generate A-token retention **and** NLL
- Domain packs register `couple-templates` into accept gate (`register-coupled-templates!`)

**Research library:**
- OCR text sidecars for McClelland 1995 and Doyle AIM-521; Forgy PDF honest failed-fetch note


## 4.3.0 — HYBRID (CLS on-the-fly learning + cognitive unit)

### Brain-inspired on-the-fly training
- **Hippocampus**: episodic ring buffer (`hippocampus-encode!`, replay corpus)
- **Neocortex**: `neocortex-consolidate!` — low-lr continuous train interleaved with replay
- TMS gates plasticity: path OUT refuses consolidation

### Cognitive unit (product path)
- `cognitive-unit` / `cognitive-turn` / `epoch-cognitive-step`
- Loop: act → encode → optional train → TMS re-check → explain
- `hybrid-demo`: refuse / allow / learn / explain
- `iface-turn` attaches `:hybrid` on every turn; `/learn` teach path
- `./bin/demo-hybrid`

### Research library
- `research/papers/` whitepapers (NeSy, CLS, continual learning, STRIPS, …)
- `research/notes/` BIBLIOGRAPHY, CLS-MAPPING, HYBRID-LOOP

### Tests
- Suite `:metis-hybrid`

## 4.2.0 — FRONTIERS (category symbols, richer GPU, remote trust, deep LM, packaging)

1. **More symbols**: `chat-ui`, `image-ingest`, `domain-pack`, `curriculum`
2. **Richer GPU**: on-device axpy + relu (+ matmul); CPU agreement; clean fail without CUDA
3. **Remote install + trust**: git/HTTP/`file://` with HMAC `symbol.sig`; unsigned remote refused
4. **Longer/deeper LM**: product defaults depth 3, seq-len 128; train records backend/op-counts
5. **Packaging**: `./bin/package-metis`, docs triad, `docs/release-memo-4.2.md`
6. Suite `:metis-frontiers`

## 4.1.0 — SYMBOLS (plugins) + optional GPU neural backend

### Symbols plugin system
- Full plugin protocol: discover, load, enable, disable, install from directory
- Homage naming: **symbols** under `symbols/<id>/manifest.lisp`
- Boot: `symbols-boot!` loads in-tree symbols; `cpu-nn` enabled by default
- Tools: `symbols-list`, `symbol-info`, `symbol-enable`, `symbol-disable`, `symbol-install`, `nn-backend`
- Iface: `/symbols list|info|enable|disable|install|backend`

### NN backends (dictated by symbols, not CLI flags)
- **cpu-nn** — pure Common Lisp (always available)
- **gpu-nn** — CUDA driver API (`libcuda.so`) + embedded PTX SGEMM; enable with `(enable-symbol! "gpu-nn")`
- `t-matmul` forward path dispatches through active NN backend; autograd backward stays on host

### Tests
- Suite `:metis-symbols` — boot, tools, CPU matmul, GPU enable (when device present), install third-party sample

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
