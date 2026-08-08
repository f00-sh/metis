## f00

Part of [f00](https://f00.sh/) · site [metis.f00.sh](https://metis.f00.sh/) · org [f00-sh/metis](https://github.com/f00-sh/metis)

# Metis 4.5.0

**Empty Common Lisp cognitive runtime.** Intelligence arrives as **sealed dual-facet symbols** you load and unload — not a frozen kitchen-sink model. Train and generate **in-process** (pure CL by default; optional CUDA as a symbol). Freeform residual chat uses a **house base LM**; specialists (reason-act, math process, extractive docs) are tool sieves. Product freeform does **not** call external LLM APIs.

| Surface | Command |
|---------|---------|
| TUI (default) | `./bin/metis` or `metis` |
| Line chat | `./bin/metis chat` |
| Symbols | `./bin/metis symbol help` |
| Tests | `./bin/metis test` |
| Multi-session | `./bin/metis epoch` |

Site: [metis.f00.sh](https://metis.f00.sh/) · Version: **4.5.0** (see [`VERSION`](VERSION))

---

## Install

```bash
# recommended
curl -fsSL https://metis.f00.sh/install.sh | bash

# pin
curl -fsSL https://metis.f00.sh/install.sh | METIS_VERSION=4.5.0 bash

# Homebrew
brew install f00-sh/tap/metis

# from source
git clone https://github.com/f00-sh/metis.git && cd metis
ln -sfn "$(pwd)" ~/quicklisp/local-projects/metis   # optional
./bin/metis version && ./bin/metis test
```

Requires **SBCL** + **Quicklisp**. Full ops: [docs/install.md](docs/install.md).

---

## Quick start

```bash
metis version          # or ./bin/metis version
metis                  # full-screen TUI
metis chat             # line interface
metis symbol help
```

### Freeform pipeline (product)

1. **NL chitchat** — greetings / identity (language symbol Use facet)  
2. **reason-act** — assert/prove/bind (`x = y` → `what is y` → composed values)  
3. **Process math** — expressions when math Process facet is on  
4. **Extractive** — answers from attached files  
5. **Knowledge-about** — dual-facet about-questions only (`what is a limit?`)  
6. **House chat spine** — in-process base LM + optional symbol model conditioners  

**Not product freeform:** external OpenAI-compatible completion as the mind.

### Symbols (train → seal → load)

```bash
./bin/metis symbol new my-domain
./bin/metis symbol train knowledge/source-kits/my-domain
./bin/metis symbol build knowledge/source-kits/my-domain
./bin/metis symbol verify knowledge/sealed/my-domain
./bin/metis symbol load knowledge/sealed/my-domain
```

Shipped math seals: `math`, `algebra`, `geometry`, `trigonometry`, `calculus` under `knowledge/sealed/`.

### Dual-facet law

| Kind | Facets |
|------|--------|
| Math | **Knowledge** + **Process** |
| Language | **Use** + **About** |
| Other domains | Knowledge by default |

Unload removes all facets for that symbol. Host LLM content biases are never injected. See [docs/SYMBOL-FACETS.md](docs/SYMBOL-FACETS.md).

### House chat + model packages

Residual open freeform uses `house-chat` (pure-CL LM). Enabling a symbol can attach a **model package** conditioner (`symbol-model-attach!` / pack with `model.ckpt` or `:model-package`) that **conditions** generation — not RAG-only residual chat.

### Chat / brain (attachments)

```text
/nn enable
@./notes/dolphins.txt
/ingest ./my-folder
/watch folder ./dropbox
/brain status
tell me about dolphins
```

---

## Architecture (one process)

| Layer | Role |
|-------|------|
| **Symbolic** | Unifier, KB, RETE, TMS, STRIPS/HTN, reason-act |
| **Neural** | Pure-CL tensors/autograd/LM train+generate; optional GPU symbol |
| **Symbols** | Sealed knowledge + plugins (cpu-nn, gpu-nn, packs) |
| **Chat spine** | House base LM for residual freeform |
| **Continuum** | EPOCH multi-session, durable LMDB |

Demo hybrid CLS: `./bin/demo-hybrid`. Research notes: `research/`.

---

## Documents

| Doc | Audience |
|-----|----------|
| [docs/overview.md](docs/overview.md) | Product map |
| [docs/install.md](docs/install.md) | Install & ops SOP |
| [docs/develop.md](docs/develop.md) | Develop & extend |
| [docs/SYMBOL-TRAINING.md](docs/SYMBOL-TRAINING.md) | Train / seal / load |
| [docs/SYMBOL-FACETS.md](docs/SYMBOL-FACETS.md) | Dual-facet + chat spine |
| [docs/SYMBOL-DOCTRINE.md](docs/SYMBOL-DOCTRINE.md) | Seal honesty |
| [docs/sop-metis-ops.md](docs/sop-metis-ops.md) · [PDF](docs/sop-metis-ops.pdf) | Operator SOP (install/run/test/deploy) |
| [docs/sop-release.md](docs/sop-release.md) | Release / packaging bump |
| [docs/sop-site-deploy.md](docs/sop-site-deploy.md) | Site deploy (Cloudflare Pages) |
| [AGENTS.md](AGENTS.md) | Agent project instructions |
| [man/metis.1](man/metis.1) | Man page |
| [packaging/README.md](packaging/README.md) | Channels & layout |
| [CHANGELOG.md](CHANGELOG.md) | History |
| [file_id.diz](file_id.diz) | Scene card |

---

## License

MIT · © contributors · [f00-sh/metis](https://github.com/f00-sh/metis)
