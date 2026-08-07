# Complementary Learning Systems → Metis

Reference: McClelland, McNaughton & O’Reilly (1995); van de Ven et al. (2020);
Shi et al. (2025); arXiv:2507.11393.

## Theory (brain)

| System | Role | Learning |
|--------|------|----------|
| **Hippocampus** | Episodic, sparse, rapid | One-shot / few-shot traces of events |
| **Neocortex** | Semantic / statistical structure | Slow interleaved update; avoids catastrophic forgetting |
| **Replay** | Hippocampus → cortex | Offline/online interleaving of old + new |

## Metis mapping (product)

| Brain | Metis |
|-------|--------|
| Hippocampus | `*hippocampus*` ring buffer of episode strings + metadata |
| Encode experience | `hippocampus-encode!` after each cognitive turn |
| Neocortex | Registered char LM (`online-lm` / session model) via pure-CL train |
| Consolidation | `neocortex-consolidate!` — few batches, low lr, **replay + new** |
| Gating plasticity | TMS `nn-path-enabled` must be IN to fire neural *and* to consolidate |
| Sleep/rest consolidation | Explicit `cognitive-unit` learn phase; optional every-N-turns |
| Pattern separation | Distinct episode IDs + source tags (user/tell/goal/error) |

## Design constraints (honest)

- Not biophysical; **functional** CLS.
- Consolidation is finite (bounded batches) — critical requirement is *on-the-fly*, not infinite pretrain.
- Catastrophic forgetting mitigation = replay of prior episodes, not EWC/full generative model (yet).
