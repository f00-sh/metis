# Metis 2.0 — ARC (Autopoietic Reflexive Continuum)

**A Common Lisp cognitive architecture whose unit of intelligence is a self-stabilizing continuum cycle:**

```
percept → RETE react → TMS validate → autopoietic repair → durable checkpoint → continue
```

## Novel intelligence thesis

**Autopoietic Reflexive Continuum (ARC)** — dual-pathway intelligence in which a **RETE-compiled reactive cortex** and a **TMS-verified deliberative validator** share **durable continuum memory** (LMDB). Contradictions trigger autopoietic repair (retract → rejoin → re-derive → checkpoint) rather than silent inconsistency.

This is not “AGI.” It is a named, runnable mechanism that no prior open CL stack shipped as one obligatory cognitive unit with formal TMS guards + RETE + durable continuum tests.

## Capabilities

| Path | Module |
|------|--------|
| RETE forward inference | `src/rete.lisp` · `forward-chain-rete` |
| Durable LMDB store | `src/durable.lisp` |
| Formal TMS properties P1–P6 | `src/tms-formal.lisp` |
| Large corpora | `knowledge/large-corpus.lisp` |
| API adversarial review + gates | `docs/adversarial-api-review.md` · `src/api.lisp` |
| ARC continuum | `src/arc.lisp` |
| STRIPS + HTN, multi-agent, frames, … | Metis 1.x baseline retained |

## Quick start

```bash
# tests (core + production + bench + further)
./bin/metis test
# or
sbcl --load bin/run-tests.lisp
```

```lisp
(ql:quickload :metis)
(in-package :metis)
(boot)
(forward-chain-rete *mind*)
(arc-boot *mind*)
(arc-cycle *arc* '((philosopher ada)))
(ask *mind* '(mortal ada))
(tms-formal-verify)
(durable-roundtrip-ok-p *mind*)
```

## HTTP API

Local by default (`127.0.0.1:7433`). Set `METIS_API_TOKEN` for bearer auth. Bodies reject `#.` / dangerous forms; rate-limited.

## Requirements

SBCL, Quicklisp, LMDB (via Quicklisp `lmdb` system + system liblmdb).

## License

MIT
