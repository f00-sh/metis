# Dual-facet product law (hard rule)

Metis is an empty, unguarded runtime. **Symbols** are owner-controlled sealed packages.
The host LLM injects **no** content biases.

## Mathematics symbols — always two facets

| Facet | Job | Ship path |
|-------|-----|-----------|
| **Knowledge** | Answer questions *about* the domain | corpus + domain-def facts → freeform knowledge |
| **Process** | **Perform** calculations | capability-gated compute (`symbol-math-answer` / engines) |

Unload a math domain → knowledge **and** compute for that domain stop.
Facts alone never count as “having calculus.”

## Language symbols — always two facets

| Facet | Job | Ship path |
|-------|-----|-----------|
| **Use** | Read, interpret, answer **in** the language | chitchat / freeform surface |
| **About** | Answer questions *about* the language | word-def, grammar notes, slang explanations |

**Slang packs** are dual-facet language registers stacked on a core language symbol
(`depends-on` core `lang-en` / `natural-language`).

### Shipped English pack stack (richer freeform)

| Pack | Role |
|------|------|
| `natural-language` | Core dual-facet English (Use dialogue + About metalanguage) — default on boot |
| `lang-en-conversation` | Extra Use phrase banks (stacked) |
| `lang-en-about` | Extra About grammar / metalanguage concepts |
| `dict-en-lite` | Word definitions (`word-def`) for About lookups |
| `slang-en-lite` | Informal register (Use+About), depends on `natural-language` |

Enable from the symbols pane or catalog. Packs contribute `(nl-phrase …)` / `(nl-concept …)` facts that merge into live banks on enable.

## Other domain symbols — default one facet

History, theology, lab notes, fringe packs: **knowledge** only, unless they ship a real procedure
(then they become dual like math).

## Manifest

```lisp
:facets (:knowledge :process)  ; math
:facets (:use :about)          ; language / slang
:facets (:knowledge)           ; default domains
```

If `:facets` omitted, Metis infers from capabilities (`symbol-default-facets-for-caps`).

## Dependency unload (refcount)

When A `depends-on` B and C also depends on B:

- Loading A or C **pins** B.
- Required deps auto-loaded from `knowledge/sealed/` load as **temporary overlays** and are marked cascade-eligible.
- Unloading A **releases A’s pin only**.
- B stays loaded while **any** loaded symbol still pins it.
- B may cascade-unload only if it was **auto-loaded as a dependency** and has **zero** remaining pins.
- Explicit user loads of B are never cascade-unloaded just because a dependent went away.
- Boot/reset clears pack enable, layer, and dep-pin session state so residual installs cannot mask auto-loaded tracking.

API: `symbol-seal-unload!`, `symbol-dep-holders`, used by `symbol-toggle!`.

## Seal honesty (unchanged)

- Opaque + tamper-evident at rest: **yes**
- Perfect anti-RE DRM: **not claimed**
- Train → seal → verify → load: see `docs/SYMBOL-TRAINING.md`
