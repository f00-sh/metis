# Metis Research Library

Curated whitepapers and notes for Metis’s hybrid (neuro-symbolic) architecture,
on-the-fly / brain-inspired learning, and the Lisp / Symbolics / MIT lineage.

## Layout

| Path | Contents |
|------|----------|
| `papers/` | Downloaded PDFs (and HTML where useful) |
| `notes/BIBLIOGRAPHY.md` | Citations, local status, **why #7 is non-goal**, code map |
| `notes/CLS-MAPPING.md` | Complementary Learning Systems → Metis hippocampus/neocortex |
| `notes/HYBRID-LOOP.md` | Cognitive unit: turn → train → TMS re-check |

## Themes

1. **Neuro-symbolic AI (2020–2025)** — hybrid reasoning + learning surveys  
2. **Complementary Learning Systems (CLS)** — hippocampus (fast) / neocortex (slow)  
3. **Continual / online learning** — catastrophic forgetting; replay; three incremental scenarios  
4. **Classical MIT/Symbolics stack** — TMS, RETE, STRIPS, Lisp machines  

## Integrity

- BIBLIOGRAPHY tracks **local vs gap** for every cited work.
- Wrong arXiv pulls (e.g. 2402.07200 mislabeled as NeSy) were removed and replaced with real NeSy surveys.
- Scanned classics (McClelland 1995, Doyle AIM-521, de Kleer ATMS) are image PDFs — readable in a viewer; text extract may be empty.
- **Still gap:** Forgy RETE 1982 full journal PDF (public mirrors 403/404); Metis already implements RETE in product.

## Quick count

See `notes/BIBLIOGRAPHY.md` for the full table. Core CLS + NeSy + classics are on disk under `papers/`.
