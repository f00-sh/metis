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

- `:decision` — `:allow` | `:refuse` | `:learn` | `:act`
- `:neural` — generate result or refuse reason
- `:learned` — train metrics or nil
- `:tms` — path IN/OUT before and after
- `:why` — human-readable justification strings
