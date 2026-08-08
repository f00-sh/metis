# Complementary Learning Systems → Metis

Primary: McClelland, McNaughton & O’Reilly (1995) — local `papers/mcclelland-1995-cls.pdf`.  
Also: van de Ven et al. (2019, 2020); Spens & Burgess (2024); Jun et al. (2025 arXiv:2507.11393);
Ramsauer et al. (2021 modern Hopfield); Shi et al. (2025).

## Theory (brain)

| System | Role | Learning |
|--------|------|----------|
| **Hippocampus** | Episodic, sparse, rapid; **pattern separation** | One-shot / few-shot traces of events |
| **Neocortex** | Semantic / statistical structure; **pattern completion** | Slow interleaved update; avoids catastrophic forgetting |
| **Replay** | Hippocampus → cortex | Offline/online interleaving of old + new |

## What the 2024–2025 papers actually prescribe (item #7 stack)

| Component | Spens & Burgess / Jun et al. | Role |
|-----------|------------------------------|------|
| Modern Hopfield / autoassociative | Hippocampal store of distinct episodes | Separation + one-shot retrieval |
| VAE / generative cortex | Slow statistical model trained by replay | Completion / synthetic rehearsal |
| Benchmarks | Split-MNIST, CIFAR-100 class-incremental | Vision CL leaderboards |

Metis **maps the functions**, not that stack (see BIBLIOGRAPHY “Why #7 is not product work”).

## Metis mapping (product — functional CLS)

| Brain | Metis |
|-------|-------|
| Hippocampus | `*hippocampus*` episodic buffer + priority + separation keys |
| Encode experience | `hippocampus-encode!` after cognitive turns / couple outcomes |
| Neocortex | Registered char LM (`online-lm`) pure-CL train |
| Consolidation | `neocortex-consolidate!` — interleaved *k*-old+1-new, bounded batches |
| Gating plasticity | TMS `nn-path-enabled` must be IN to fire neural *and* to consolidate |
| Sleep/rest | `sleep-consolidate!` offline prioritized replay |
| Pattern separation | `:goal` / `:context` / `:tms-state` (+ source priority) |
| Pattern completion | Constrained generate: cue + TMS-IN facts (not VAE decode) |
| CLS proof | `hybrid-forget-test` — fair A→B, only replay on/off |

## Design constraints (honest)

- Not biophysical; **functional** CLS under Decision B (pure CL).
- Consolidation is finite (bounded batches) — critical requirement is *on-the-fly*, not infinite pretrain.
- Catastrophic forgetting mitigation = **prioritized text/episode interleaved replay**, not EWC / full generative VAE / MHN product path.
- Item **#7** (VAE+Hopfield+CIFAR theater) stays non-goal until a deliberate product decision expands the neural substrate.
