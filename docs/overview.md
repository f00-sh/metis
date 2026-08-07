# Metis — Overview

Metis is a **Common Lisp cognitive architecture**: symbolic reasoning (unifier, KB, RETE, TMS, STRIPS/HTN), multi-session continuum (ARC/EPOCH), interactive sessions, in-process neural training, and a **symbols** plugin system (homage to Symbolics).

## Product surface

| Surface | Entry |
|---------|--------|
| REPL mind | `./bin/metis repl` |
| Interactive iface | `./bin/metis iface` |
| Multi-session EPOCH | `./bin/metis epoch` |
| Tests | `./bin/metis test` |
| Packaged image | `./bin/package-metis` → `build/metis.image` |

## Core ideas

1. **One process** — symbolic mind and trainable models share runtime state.
2. **Decision B** — default train/infer is pure Common Lisp (no Python).
3. **TMS policy** — neural generate is gated by truth-maintenance (`nn-path-enabled`).
4. **Symbols** — plugins install/enable capabilities (CPU/GPU backends, chat UI, image ingest, domain packs, curricula).
5. **GPU is optional** — enable the `gpu-nn` symbol when CUDA is present; CPU remains default.

## Version line

This documentation triad tracks the **4.2 FRONTIERS** line: category symbols, richer GPU ops, remote install+trust, deeper/longer LM defaults, and product packaging.
