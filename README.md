## f00

Part of [f00](https://f00.sh/) · site [metis.f00.sh](https://metis.f00.sh/) · org [f00-sh/metis](https://github.com/f00-sh/metis)

# Metis 4.4 — THEORY

**Cognitive architecture with in-process trainable models and a plugin system** — pure Common Lisp neural training by default, optional CUDA GPU acceleration as a **symbol** (plugin), bound to a full symbolic control stack (unifier, KB, RETE, TMS, STRIPS/HTN, durable continuum, multi-session EPOCH, interactive interface).

No Python. No external ML runtime required for the default path. Training and generation run inside the Metis process. GPU is an installable/enableable **symbol**, not a hard dependency.

**Public CLS / THEORY contract:** prioritized interleaved replay, fair forget-test (identical hyperparams; only replay on/off), path-IN `:coupled-reject`, structured explain objects, soft text latents, domain couple-templates. **#7 non-goals:** no product VAE + Modern Hopfield + CIFAR-100 stack — pure-CL (Decision B) remains default train/infer.

Marketplace is **in-tree** (free open catalog — no payments). **Knowledge symbols** are sealed, owner-controlled packages (not kitchen-sink weights).

**4.4 THEORY CLS contract (shipped):** Complementary Learning Systems–style **on-the-fly training** — hippocampus (fast episodes) + neocortex (slow consolidate with replay) + TMS re-check — as one cognitive unit. Demo: `./bin/demo-hybrid` (refuse / allow / learn / explain). Research PDFs under `research/`.

### Dual-facet product law

- **Math symbols** always **two facets**: **Knowledge** (explain) + **Process** (compute). Unload removes both.
- **Language symbols** always **two facets**: **Use** (speak/read in the language) + **About** (metalanguage). Slang packs are dual-facet registers.
- **Other domains** default to **knowledge only**.
- See [docs/SYMBOL-FACETS.md](docs/SYMBOL-FACETS.md). Host LLM biases are never injected.

### Sealed symbols (train → seal → load)

Metis itself knows nothing. You **train** source kits and ship **opaque sealed packages** (hash + signature; open-sealed or private-sealed). Detailed author guide:

- **[docs/SYMBOL-TRAINING.md](docs/SYMBOL-TRAINING.md)** — full step-by-step training
- **[docs/SYMBOL-DOCTRINE.md](docs/SYMBOL-DOCTRINE.md)** — product doctrine

```bash
./bin/metis symbol help
./bin/metis symbol new my-domain
./bin/metis symbol train knowledge/source-kits/my-domain
./bin/metis symbol build knowledge/source-kits/my-domain
./bin/metis symbol verify knowledge/sealed/my-domain
./bin/metis symbol load knowledge/sealed/my-domain
```

Shipped math domain symbols (open educational citations): `math`, `algebra`, `geometry`, `trigonometry`, `calculus` under `knowledge/source-kits/` + `knowledge/sealed/`.

Also: category plugins, GPU axpy/relu, remote install+trust, deep LM defaults, packaging.

## What this is

Metis is not an “X is Y” rule shell wearing a modern label. 4.0 adds a real neural substrate:

| Layer | Capability |
|-------|------------|
| **Neural (`metis.nn`)** | Dense tensors, reverse-mode autograd, multi-layer LM with causal context windows, linear/embedding/MLP, Adam/SGD, continuous train, checkpoint/registry, TMS-gated generate |
| **Symbolic control** | Unification, knowledge base, frames, forward + RETE, backward chaining, STRIPS, HTN, JTMS + formal properties |
| **Continuum** | ARC dual-pathway mind, LMDB durable memory, EPOCH multi-session resume, TMS-guarded self-modification |
| **Interface** | Multi-turn sessions, file/context/photo attach, `/need` self-accommodation, train/generate commands, HTTP API |

The groundbreaking claim is architectural: **trainable models live in the same runtime as the symbolic mind** that plans, justifies, retracts, and self-modifies — one process, one language, shared KB/TMS facts about model readiness.

## Install

```bash
# curl | bash
curl -fsSL https://metis.f00.sh/install.sh | bash

# Homebrew
brew install f00-sh/tap/metis

# AUR-style PKGBUILD (org-keyed)
# see packaging/aur or https://github.com/f00-sh/aur-metis
```

Full guide: [docs/install.md](docs/install.md).

## Quick start

```bash
metis version                     # after install — or ./bin/metis version
./bin/metis                       # TUI (default)
./bin/metis chat                  # line interface
./bin/metis epoch                 # multi-session open pursuit
./bin/metis test                  # full suite
```

### English Q&A + background brain (real train, not just context)

The iface **brain** thread runs continuously: folder watches, train queue, idle consolidation — while you keep chatting.

```bash
./bin/metis                 # default = pure Common Lisp TUI (chat | status + REPL)
./bin/metis chat            # line mode (no TUI) — also: line | notui | repl
```

**TUI** (default): ANSI/Unicode borders, color, animated splash. Left = chat; right = status (mind/brain/files) over REPL. Tab focus; Enter send; `/quit` or Esc to leave. All CL.

```
/nn enable
@./notes/dolphins.txt        # drop a file in chat → extract + HARD continuous train
/attach ./report.pdf         # same (shortcut)
/ingest ./my-folder          # whole folder: extract + train each file
/watch folder ./dropbox      # background: new drops train immediately (no poll)
/brain status                # queue / jobs-done / watches
tell me about dolphins
(tell (species dolphin mammal))   # classic mind forms still work (leading '(')
```

| Command | What it does |
|---------|----------------|
| `@PATH` or `/attach PATH` | Attach + **hard** `nn-continuous-train` on brain queue |
| `/attach folder PATH` | Recursive attach + train |
| `/watch folder PATH` | Brain polls ~3×/sec; new files train as they land |
| `/train text\|file\|attachments` | Explicit hard train (queued, non-blocking) |
| `/brain start\|stop\|status` | Control background learner |

Supported extraction: text/code, PDF (`pdftotext`), CSV/TSV, XLSX/DOCX (stdlib Python helpers under `scripts/`), UTF-8 fallback for unknown non-binary files.

Freeform English order: **math** → **extractive multi-sentence answers from attachments** → KB facts → optional **LLM** under TMS → local pure-CL generate last.

**LLM (SpaceXAI / xAI by default):** set a key in-app or via env — auto-enables when present.

```text
/llm status
/llm key xai-…              # saves ~/.metis/llm.key (mode 600) + enables
/llm model grok-3
/llm base https://api.x.ai/v1
/llm clear
```

Also: `export XAI_API_KEY=…`, project `.env`, or `~/.metis/llm.key`. Default base `https://api.x.ai/v1`, model `grok-3`.

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
