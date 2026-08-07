# Bibliography (Metis research)

## Neuro-symbolic (recent)

| Local file | Work | Relevance |
|------------|------|-----------|
| `papers/2501.05435-neurosymbolic-ai-2024-review.pdf` | Colelough & Regli, *Neuro-Symbolic AI in 2024: A Systematic Review* (arXiv:2501.05435) | Taxonomy of NeSy; meta-cognition gap → Metis TMS + explain |
| `papers/nai-survey-neurosymbolic.pdf` | *A survey of neurosymbolic AI* (NeSy journal, 2020–2025) | Foundations for hybrid design |
| `papers/ijcai2025-nesy-task-survey.pdf` | Delvecchio et al., IJCAI-25 NeSy task-directed survey | Task-level hybrid patterns |
| `papers/2402.07200-nesy-survey.pdf` | arXiv:2402.07200 (if full PDF) | Additional NeSy survey |

## Continual / brain-inspired learning

| Local file | Work | Relevance |
|------------|------|-----------|
| `papers/vandeven-brain-inspired-replay-2020.pdf` | van de Ven et al., *Brain-inspired replay…*, Nat Commun 2020 | Generative/hippocampal replay → Metis episode replay |
| `papers/41467-025-56405-9.pdf` | Shi et al., hybrid nets for continual learning (Nat Commun 2025) | CLS in modern architectures |
| `papers/2507.11393-cls-pattern-separation.pdf` | *A Neural Network Model of Complementary Learning Systems* (2025) | Pattern separation/completion |
| `papers/2302.00487-continual-learning-survey.pdf` | Continual learning survey (arXiv) | Online learning landscape |

## Classical MIT / symbolic (torch)

| Local file | Work | Relevance |
|------------|------|-----------|
| `papers/fikes-nilsson-strips.pdf` | Fikes & Nilsson, STRIPS | Metis planner lineage |
| Doyle AIM-521 / de Kleer ATMS | Truth maintenance | Metis JTMS-lite + neural gate |
| Forgy RETE | Production match | Metis RETE cortex |
| Symbolics 3600 / Genera literature | Interactive Lisp mind | Symbols plugins, image, REPL culture |
| McClelland, McNaughton & O’Reilly 1995 | *Why there are complementary learning systems…* | **Primary brain model for Metis online learn** |

## Canonical external links (if download failed)

- McClelland et al. 1995 CLS: https://stanford.edu/~jlmcc/papers/McCMcNOrei95.pdf  
- Doyle TMS AIM-521: https://dspace.mit.edu/handle/1721.1/5733  
- Colelough NeSy 2024: https://arxiv.org/abs/2501.05435  
- van de Ven replay: https://doi.org/10.1038/s41467-020-17866-2  

## Metis implementation map

| Paper idea | Metis code |
|------------|------------|
| Hippocampus: fast episodic encode | `hippocampus-encode!` in `src/hybrid.lisp` |
| Neocortex: slow consolidation | `neocortex-consolidate!` (low-lr continuous train) |
| Replay interleaved with new | `hippocampus-replay-corpus` |
| Justification / retract | TMS `nn-path-enabled` + recheck after train |
| Hybrid agent loop | `cognitive-unit` / `cognitive-turn` |
