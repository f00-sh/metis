# Metis 3.1 — INTERFACE

**Full interactive cognitive product surface** on the EPOCH/ARC mind:

- Multi-turn chat **without process restart**
- Attach **files**, freeform **context**, and **photos**
- Turns drive real tell/ask/pursue cognition
- **Self-accommodation**: `/need CAP` → TMS-guarded self-mod + tool/skill install

```bash
./bin/metis iface                 # interactive REPL
./bin/metis iface --demo          # multi-turn demo
./bin/iface --drive "status" "(tell (hi))" "(ask (hi))"
```

### Commands (iface)

| Input | Effect |
|-------|--------|
| `/attach file PATH [caption]` | text/binary file → session + KB |
| `/attach photo PATH [caption]` | image provenance (path/type/size) |
| `/context TEXT` | freeform context material |
| `/attachments` | list session attachments |
| `/read ID` | read attachment text/meta |
| `/ask` `/tell` `/goal` | cognition |
| `/need CAPABILITY` | self-accommodate unknown skill |
| `(lisp forms…)` | mind language |

### Architecture stack

INTERFACE (3.1) → EPOCH (3.0) → ARC/RETE/TMS/LMDB (2.0) → cognitive kernel (1.x)

## Tests

```bash
./bin/metis test
# core · production · bench · further · epoch · iface
```

## License

MIT
