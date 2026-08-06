# Metis 3.0 — EPOCH

**Enduring Process of Open Cognitive Homotopy**

Flagship post-ARC program: multi-session open cognitive pursuit that can **suspend, restart, and resume** past any single continuum cycle, treating the mind’s **own code as cognitive material**, with **TMS-guarded self-modification**.

```
open goals → ARC cycle + pursue → introspect self-code →
  guarded self-mod → durable suspend → [process exit] → resume session N+1
```

## Why this is farther than 2.0 ARC

| | ARC (2.0) | EPOCH (3.0) |
|--|-----------|-------------|
| Unit of cognition | single-session continuum cycle | multi-session open pursuit |
| Process restart | not an obligatory unit | **suspend/resume across process** |
| Own code as material | optional introspection | **ingest exports as facts** |
| Self-mod | rewrite-rule tools | **TMS-integrity-gated + rollback** |

## Flagship entry

```bash
./bin/epoch --path /tmp/epoch-store --id flagship --steps 12
./bin/metis epoch --resume --path /tmp/epoch-store --id flagship
```

```lisp
(ql:quickload :metis)
(metis:epoch-flagship :durable-path "/tmp/epoch-store" :goals '((clear a)))
(metis:epoch-leap-resume-demo "/tmp/epoch-leap/" :id "demo")
```

## Architecture (kept from 2.0)

RETE · LMDB durable · JTMS formal P1–P6 · HTN/STRIPS · multi-agent · API security · ARC continuum

## Tests

```bash
./bin/metis test
# core · production · bench · further · epoch
```

## Thesis

See `metis:epoch-thesis` / `*epoch-thesis*` in `src/epoch.lisp`.

## License

MIT
