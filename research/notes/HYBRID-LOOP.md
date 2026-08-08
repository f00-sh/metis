# Hybrid cognitive unit

## Unit (obligatory)

```
percept/text
    → symbolic act (tell/ask/plan/iface op)
    → neural propose? (generate)  [TMS allow/refuse]
    → encode episode (hippocampus)
    → optional consolidate (neocortex train + replay)
    → TMS re-check integrity
    → explain {allow|refuse|learn|why}
```

## Entry points

| API | Role |
|-----|------|
| `cognitive-unit` | Core loop on a mind + text |
| `cognitive-turn` | Session wrapper (iface) |
| `epoch-cognitive-step` | EPOCH step + consolidation |
| `hybrid-demo` | refuse / allow / learn / explain |

## Explain contract

Return plist always includes:

- `:decision` — `:allow` | `:refuse` | `:learn` | `:act` | `:coupled-reject`
- `:neural` — generate result or refuse reason
- `:learned` — train metrics or nil
- `:tms` — path IN/OUT before and after
- `:explain` — structured object (`make-explain-object`: supporters, tms-label, episodes-used, weights-stepped)
- `:why` — human-readable justification strings

Coupled path: `hybrid-coupled-propose` → neural draft optional; `hybrid-coupled-accept-p` (unify templates / prove) is the fail-capable gate; learn only on accept.
