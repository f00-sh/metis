# Metis 4.2 — FRONTIERS

**Cognitive architecture with in-process trainable models and a plugin system** — pure Common Lisp neural training by default, optional CUDA GPU acceleration as a **symbol** (plugin), bound to a full symbolic control stack (unifier, KB, RETE, TMS, STRIPS/HTN, durable continuum, multi-session EPOCH, interactive interface).

No Python. No external ML runtime required for the default path. Training and generation run inside the Metis process. GPU is an installable/enableable **symbol**, not a hard dependency.

**4.2 adds:** category symbols (`chat-ui`, `image-ingest`, `domain-pack`, `curriculum`), richer GPU ops (axpy/relu), remote symbol install with HMAC trust, deeper/longer LM defaults (depth 3 / seq-len 128), and packaging (`./bin/package-metis` + docs triad).

## What this is

Metis is not an “X is Y” rule shell wearing a modern label. 4.0 adds a real neural substrate:

| Layer | Capability |
|-------|------------|
| **Neural (`metis.nn`)** | Dense tensors, reverse-mode autograd, multi-layer LM with causal context windows, linear/embedding/MLP, Adam/SGD, continuous train, checkpoint/registry, TMS-gated generate |
| **Symbolic control** | Unification, knowledge base, frames, forward + RETE, backward chaining, STRIPS, HTN, JTMS + formal properties |
| **Continuum** | ARC dual-pathway mind, LMDB durable memory, EPOCH multi-session resume, TMS-guarded self-modification |
| **Interface** | Multi-turn sessions, file/context/photo attach, `/need` self-accommodation, train/generate commands, HTTP API |

The groundbreaking claim is architectural: **trainable models live in the same runtime as the symbolic mind** that plans, justifies, retracts, and self-modifies — one process, one language, shared KB/TMS facts about model readiness.

## Quick start

```bash
./bin/metis repl                  # Lisp mind REPL
./bin/metis iface                 # interactive product surface
./bin/metis epoch                 # multi-session open pursuit
./bin/metis test                  # full suite (core · production · bench · further · epoch · iface · nn)
```

### Train and generate (no Python)

```bash
./bin/metis iface
```

```
/train text the quick brown fox jumps over the lazy dog again and again
/generate session-lm the
/nn list
/train file /path/to/corpus.txt my-model
/generate my-model Once upon
```

Programmatic:

```lisp
(ql:quickload :metis)
(metis:boot)

;; Multi-layer LM + context window (pure CL)
(metis:nn-train-language-model
  (uiop:read-file-string "path/to/corpus.txt")
  :name "corpus-lm"
  :epochs 8
  :hidden 256
  :seq-len 128          ; causal context window
  :depth 3)             ; hidden layers

;; Continuous train on more corpus (same registered model)
(metis:nn-continuous-train more-text :name "corpus-lm" :epochs 4)

;; Attachments → corpus → continuous train
(let ((s (metis:session-ensure)))
  (metis:session-attach-file s "path/to/a.txt")
  (metis:session-attach-context s "more notes…")
  (metis:nn-train-from-session s :name "session-lm" :depth 2 :seq-len 64))

;; Sample (TMS-gated: nn-path-enabled must be IN on the mind)
(metis:nn-generate "corpus-lm" :prompt "the " :length 200)
(metis:nn-disable-path)   ; retract policy → generate refuses
(metis:nn-enable-path)    ; reinstate

;; Nonlinear training verification (XOR)
(metis:nn-train-mlp-xor :epochs 600)
```

Checkpoints land under `models/` in the system tree (or `*nn-model-dir*`).

### Interactive surface (from 3.1)

| Input | Effect |
|-------|--------|
| `/attach file PATH [caption]` | file → session + KB |
| `/attach photo PATH [caption]` | image provenance |
| `/context TEXT` | freeform context |
| `/ask` `/tell` `/goal` | cognition |
| `/need CAPABILITY` | TMS-guarded self-accommodate |
| `/train text …` / `/train file PATH [name]` | continuous-train multi-layer LM |
| `/train attachments [name]` | attachment corpus → continuous train |
| `/generate NAME [prompt]` | TMS-gated sample from registered model |
| `/nn list` | registered models |
| `/nn enable` / `/nn disable` | TMS neural-path policy |
| `(lisp forms…)` | mind language |

HTTP (Hunchentoot, default `127.0.0.1:7433`): session create/turn/attach under `/v1/session/*`.

## Architecture stack

```
NEURAL 4.0  — pure-CL autograd + train/infer + registry + mind bridge
    ↑
INTERFACE 3.1 — multi-turn sessions, attachments, self-accommodation
    ↑
EPOCH 3.0 — multi-session open pursuit, self-code ingest, TMS-guarded self-mod
    ↑
ARC 2.0 — RETE cortex + TMS deliberation + LMDB continuum
    ↑
Kernel 1.x — unifier, KB, planner, HTN, tools, security
```

## Neural substrate (`src/nn/`)

| Module | Role |
|--------|------|
| `package.lisp` | `metis.nn` public API |
| `tensor.lisp` | dense double-float tensors, reverse-mode AD, topological `backward` |
| `ops.lisp` | matmul, elementwise, ReLU, softmax, cross-entropy, MSE, embedding lookup |
| `module.lisp` | linear, embedding, MLP, SGD, Adam |
| `train.lisp` | char vocab, multi-layer LM + causal context, `train-lm!`, `lm-generate`, checkpoints, registry |
| `bridge.lisp` | continuous train, session corpus, TMS-gated generate, tools, iface |

### Symbols (plugins)

Plugins live in `symbols/<id>/` with a `manifest.lisp`. Boot discovers and loads them. **cpu-nn** is always enabled; **gpu-nn** is optional.

```bash
./bin/metis iface
# /symbols list
# /symbols enable gpu-nn
# /symbols backend
# /symbols disable gpu-nn
# /symbols install /path/to/my-symbol
```

```lisp
(metis:symbol-list-info)
(metis:enable-symbol! "gpu-nn")   ; RTX / libcuda — matmul on device
(metis:nn-backend-status)
(metis:disable-symbol! "gpu-nn")  ; falls back to cpu-nn
```

Write your own: directory + `manifest.lisp` calling `metis.symbols:register-symbol!` with hooks (`:activate`, `:deactivate`, capabilities like `:nn-backend`, `:tool`, `:iface`).

### CPU / GPU

| Symbol | Role |
|--------|------|
| **cpu-nn** (default) | Pure CL dense tensors + reverse-mode AD on host |
| **gpu-nn** (optional) | CUDA driver PTX SGEMM for matmul forward; enable when `libcuda` + GPU present |

The active symbol **dictates** the compute path. No global “GPU default that breaks laptops.”

## Tests

```bash
./bin/metis test
# core · production · bench · further · epoch · iface · nn
```

Suite `:metis-nn` covers autograd gradients, XOR convergence, LM train/generate, checkpoint round-trip, tools-on-boot.

## License

MIT
