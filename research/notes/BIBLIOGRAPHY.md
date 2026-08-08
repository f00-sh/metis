# Bibliography (Metis research)

Local PDFs live under `research/papers/`. Status: **local** = readable PDF on disk;
**gap** = still only external (download failed / paywall / scan pending).

## Neuro-symbolic (recent)

| Local file | Work | Relevance | Status |
|------------|------|-----------|--------|
| `2501.05435-neurosymbolic-ai-2024-review.pdf` | Colelough & Regli, *Neuro-Symbolic AI in 2024: A Systematic Review* (arXiv:2501.05435) | Taxonomy; **meta-cognition** + multi-system integration gaps → Metis TMS, metrics, explain | local (20pp) |
| `nai-survey-neurosymbolic.pdf` | *A survey of neurosymbolic artificial intelligence* (journal) | Foundations for hybrid design | local (68pp) |
| `ijcai2025-nesy-task-survey.pdf` | Delvecchio et al., IJCAI-25 NeSy task-directed survey | Task-level hybrid patterns | local (9pp) |
| `2105.05330-neurosymbolic-survey.pdf` | Sarker et al., *Neuro-Symbolic AI: Current Trends* (arXiv:2105.05330) | Conference-map of NeSy strands | local (11pp) |
| `2305.00813-nesy.pdf` | Sheth, Roy & Gaur, *Neurosymbolic AI — Why, What, and How* (arXiv:2305.00813) | Compact NeSy framing | local (6pp) |

> Removed mis-download: arXiv:2402.07200 was **not** a NeSy survey (quantization CV paper). Replaced with 2105.05330 + 2305.00813.

## Continual / brain-inspired learning (CLS lineage)

| Local file | Work | Relevance | Status |
|------------|------|-----------|--------|
| `mcclelland-1995-cls.pdf` | McClelland, McNaughton & O’Reilly (1995), *Why there are complementary learning systems…* Psych Review | **Primary CLS theory** — hippo fast / neo slow / interleaved consolidation | local (39pp, scanned) |
| `vandeven-brain-inspired-replay-2020.pdf` | van de Ven et al., Nat Commun 2020 | Generative / internal replay; **CIFAR-100** class-incremental scale | local (14pp) |
| `vandeven-three-types-incremental-2019.pdf` | van de Ven & Tolias, *Three scenarios for continual learning* (arXiv:1904.07734) | Task- / domain- / class-incremental taxonomy | local (18pp) |
| `2507.11393-cls-pattern-separation.pdf` | Jun et al. (2025), *A Neural Network Model of CLS: Pattern Separation and Completion* | **VAE + Modern Hopfield** for separation/completion; Split-MNIST ~90% | local (7pp) |
| `spens-burgess-2024-memory.pdf` | Spens & Burgess, Nat Hum Behav 2024 | Hippocampal replay trains cortical **generative** models (VAE + autoassociative memory) | local (20pp, OA Nature) |
| `ramsauer-2021-hopfield.pdf` | Ramsauer et al., *Hopfield Networks is All You Need* (arXiv:2008.02217) | Modern continuous Hopfield ≡ transformer attention | local (94pp) |
| `41467-025-56405-9.pdf` | Shi et al., Nat Commun 2025, corticohippocampal hybrid (ANN+SNN) | Modern bio-hybrid continual learning | local (14pp) |
| `2302.00487-continual-learning-survey.pdf` | Wang et al., *A Comprehensive Survey of Continual Learning* | CL method landscape | local (33pp) |

## Classical MIT / symbolic (torch)

| Local file | Work | Relevance | Status |
|------------|------|-----------|--------|
| `fikes-nilsson-strips.pdf` | Fikes & Nilsson, STRIPS | Metis planner lineage | local (20pp) |
| `doyle-aim-521.pdf` | Doyle, AIM-521 *A Truth Maintenance System* | JTMS lineage → Metis TMS / `nn-path-enabled` | local (45pp, scanned) |
| `dekleer-atms-1986.pdf` | de Kleer ATMS (CSD-86-290 / related) | Assumption-based TMS (deeper than Metis JTMS-lite) | local (11pp, scanned) |
| — | Forgy, *Rete* (AI Journal 1982) | Metis RETE cortex | **gap** — see `papers/FORGY-RETE-1982-FETCH.md` (403/404/429); product implements RETE |
| `mcclelland-1995-cls.txt` | OCR sidecar (pages 1–10) | Greppable full-text extract | local |
| `doyle-aim-521.txt` | OCR sidecar (pages 1–8) | Greppable full-text extract | local |
| — | Symbolics / Genera literature | Interactive Lisp mind | **gap** (docs scattered; product has symbols plugins) |

## Canonical external links (gaps / verification)

- McClelland et al. 1995: https://stanford.edu/~jlmcc/papers/McCMcNOrei95.pdf (also local via UCI course mirror)
- Spens & Burgess 2024 OA: https://www.nature.com/articles/s41562-023-01799-z.pdf
- Doyle AIM-521: https://dspace.mit.edu/handle/1721.1/5733
- Colelough NeSy 2024: https://arxiv.org/abs/2501.05435
- van de Ven replay: https://doi.org/10.1038/s41467-020-17866-2
- Ramsauer Hopfield: https://arxiv.org/abs/2008.02217
- Jun et al. CLS VAE+MHN: https://arxiv.org/abs/2507.11393

## Why theory item **#7** is *not* product work

Item #7 in the Metis theory plan is an explicit **non-goal**:

> Full **VAE + Modern Hopfield** CLS stack; **class-incremental CIFAR-100** product benchmarks; cuDNN-scale generative replay; pure “more layers / longer context” without separation/replay metrics.

That is **not** “we forgot the papers.” It is a deliberate scope cut after reading those papers:

| Paper asks for | What it is | Why Metis does **not** ship it as product (yet) |
|----------------|------------|--------------------------------------------------|
| **VAE** neocortex (Spens & Burgess; Jun et al.) | Probabilistic encoder/decoder for generative replay of sensory latents | Metis Decision B is **pure-CL dense char LM + reverse-mode AD**, not a VAE training stack; no GPU-required generative decoder; episode text replay already tests CLS *function* |
| **Modern Hopfield** hippocampus (Ramsauer; Jun et al.) | Continuous associative memory, transformer-attention equivalence, exponential capacity claims | Would be a second neural substrate + large matmul kernels; Metis hippocampus is **symbolic episodic buffer** with priorities/keys (functional separation), not an MHN layer |
| **CIFAR-100 / Split-MNIST class-incremental** (van de Ven; Jun et al.) | Vision CL leaderboards, 100-way incremental accuracy | Product path is **language + symbolic mind**, not ImageNet-scale vision; fair **forget-test on char LM A→B** is the shipped CLS metric, not CIFAR top-1 |
| Full generative replay at scale | Train generator on all past tasks | Boundedness + on-the-fly requirement; text/episode prioritized interleaved replay is the chosen minimal-but-real CLS |

**What we *did* implement from the same literature (items 1–6):** functional CLS (hippo encode / neo consolidate), prioritized interleaved *k*-old+1-new replay, separation keys, fair forget-test, meta metrics + TMS self-model, structured explain, neural draft → symbolic accept/reject.

## Metis implementation map (post 4.4 THEORY)

| Paper idea | Metis code |
|------------|------------|
| Hippocampus: fast episodic encode | `hippocampus-encode!` (`src/hybrid.lisp`) |
| Priority / error bias for replay | `%episode-priority`, `hippocampus-sample-prioritized` |
| Interleaved *k* old + 1 new | `hippocampus-interleaved-batches`, `neocortex-consolidate!` |
| Pattern separation keys | `:goal` / `:context` / `:tms-state` on episodes |
| Pattern completion (constrained) | generate cue + TMS-IN facts (not VAE decode) |
| Fair CLS forget-test | `hybrid-forget-test` (identical hyperparams; only replay on/off) |
| Meta-cognition / self-model | `hybrid-metrics*`, `hybrid-metrics-adjust!` → TMS `hybrid-mode` / `learn-rate` |
| Trustworthy explain | `make-explain-object` |
| Coupled NeSy gate | `hybrid-coupled-accept-p` + `hybrid-coupled-propose` |
| Justification / retract | TMS `nn-path-enabled`, `nn-disable-path-meta` |
| Offline sleep replay | `sleep-consolidate!` |
| STRIPS / RETE / TMS classics | `src/planner*`, `src/rete.lisp`, `src/tms*.lisp` |
