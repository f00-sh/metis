# Metis — Overview

**Version: 4.5.0**

Metis is an **empty Common Lisp cognitive runtime**. The host injects no domain content. You load **sealed dual-facet symbols** (and optional plugins). Training and generation of the house language model run **in-process** (Decision B: pure CL default; CUDA optional via the `gpu-nn` symbol).

## Product surfaces

| Surface | Entry |
|---------|--------|
| TUI | `./bin/metis` (default) |
| Line chat | `./bin/metis chat` |
| Symbols CLI | `./bin/metis symbol …` |
| EPOCH multi-session | `./bin/metis epoch` |
| Tests | `./bin/metis test` |
| Packaged image | `./bin/package-metis` → `build/metis.image` |
| Site | [https://metis.f00.sh/](https://metis.f00.sh/) |

## Core ideas

1. **One process** — symbolic mind and trainable models share runtime state.  
2. **Decision B** — default train/infer is pure Common Lisp (no Python required).  
3. **TMS policy** — neural generate is gated by `nn-path-enabled`.  
4. **Symbols** — sealed knowledge packages + plugins (backends, UI, packs).  
5. **Dual-facet law** — math = Knowledge+Process; language = Use+About.  
6. **House chat spine** — residual freeform uses in-process house LM; external API is **not** the product freeform mind.  
7. **reason-act** — assert/prove/bind composition for session equalities (not fact regurgitation).  
8. **GPU is optional** — enable `gpu-nn` when CUDA is present.

## Freeform order

```
task-prepare → chitchat → reason-act → process math
  → extractive attachments → about-knowledge → house-chat spine
```

## Doc map

| Doc | Use |
|-----|-----|
| [install.md](install.md) | Install & run |
| [develop.md](develop.md) | Extend symbols / NN |
| [SYMBOL-TRAINING.md](SYMBOL-TRAINING.md) | Author seals |
| [SYMBOL-FACETS.md](SYMBOL-FACETS.md) | Facets + spine |
| [SYMBOL-DOCTRINE.md](SYMBOL-DOCTRINE.md) | Trust honesty |
| [sop-metis-ops.md](sop-metis-ops.md) | Day-to-day ops |
| [sop-release.md](sop-release.md) | Release bump |
| [sop-site-deploy.md](sop-site-deploy.md) | Deploy site |

## Version line

This triad tracks **4.5.0** (sealed dual-facet symbols, reason-act, house chat spine, packaging channels). Historical memos under `docs/release-memo-*.md` are archives, not the current line.
