# Metis 4.0 — NEURAL

**Cognitive architecture with in-process trainable models** — pure Common Lisp neural training and inference, bound to a full symbolic control stack (unifier, KB, RETE, TMS, STRIPS/HTN, durable continuum, multi-session EPOCH, interactive interface).

No Python. No external ML runtime required. Training and generation run inside the Metis process. Optional external LLM remains available when keys are present; it is not the substrate.

## What this is

Metis is not an “X is Y” rule shell wearing a modern label. 4.0 adds a real neural substrate:

| Layer | Capability |
|-------|------------|
| **Neural (`metis.nn`)** | Dense tensors, reverse-mode autograd, linear/embedding/MLP, Adam/SGD, character language models, checkpoint save/load, model registry |
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

;; Train a character language model on a corpus string
(metis:nn-train-language-model
  (uiop:read-file-string "path/to/corpus.txt")
  :name "corpus-lm"
  :epochs 8
  :hidden 256
  :seq-len 64)

;; Sample
(metis:nn-generate "corpus-lm" :prompt "the " :length 200)

;; Nonlinear training verification (XOR)
(metis:nn-train-mlp-xor :epochs 600)

;; Tools on a booted mind
(metis:list-tools metis:*mind*)  ; includes nn-train-text, nn-train-file, nn-generate, nn-list
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
| `/train text …` / `/train file PATH [name]` | in-process LM train |
| `/generate NAME [prompt]` | sample from registered model |
| `/nn list` | registered models |
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
| `train.lisp` | char vocab/corpus, language model, `train-lm!`, `lm-generate`, checkpoints, registry |
| `bridge.lisp` | Metis tools, iface commands, KB/TMS facts for trained models |

## Tests

```bash
./bin/metis test
# core · production · bench · further · epoch · iface · nn
```

Suite `:metis-nn` covers autograd gradients, XOR convergence, LM train/generate, checkpoint round-trip, tools-on-boot.

## License

MIT
