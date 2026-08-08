# Release memo — Metis 4.4.0 THEORY (CLS contract)

## Contract

4.4.0 **THEORY** is the shipped Complementary Learning Systems product surface:

| Capability | Entry points |
|------------|--------------|
| Fair forget-test | `hybrid-forget-test` — identical B-phase hyperparams; only `:replay` differs |
| Force no-replay | `neocortex-consolidate!` … `:replay nil` |
| Path-IN couple reject | `hybrid-coupled-propose` → `:coupled-reject` when templates/prove fail |
| Explain | `make-explain-object` on cognitive unit and couple outcomes |
| Soft latent (text) | `episode-summary-key`, encode `:summary`/`:key`, interleaved `use-summary` |
| Separation metric | `hybrid-separation-probe` (NLL + A-token retention) |
| Domain couple templates | `domain-pack-load` + `register-coupled-templates!` |

## Non-goals (#7)

**Not shipped:** product VAE + Modern Hopfield + CIFAR-100 / vision class-incremental leaderboards.  
Pure-CL train/infer remains the default substrate (Decision B).

## Frontiers surfaces

- Society multi-mind trust: `society-trust!`, `society-trust-p`, `society-trusted-send`
- Marketplace catalog: `symbol-marketplace-catalog`
- Longer context with metrics: `hybrid-long-context-train!`

## Tests

- `:metis-hybrid` — CLS + soft latent + separation + domain templates
- `:metis-frontiers` — trust + marketplace + curriculum
