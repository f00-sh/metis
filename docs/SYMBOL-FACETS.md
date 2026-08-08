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

## Seal honesty (unchanged)

- Opaque + tamper-evident at rest: **yes**
- Perfect anti-RE DRM: **not claimed**
- Train → seal → verify → load: see `docs/SYMBOL-TRAINING.md`
