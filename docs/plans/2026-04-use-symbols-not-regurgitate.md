# Plan: Use symbols (compose / prove / solve) — not regurgitate facts

**Status:** APPROVED  
**Date:** 2026-04-08 (session)  
**Approved options:** canonical `(= a b)` + bidirectional var edges; Phase 3 single-turn multi-clause; version bump deferred to release workflow.  
**Product gap:** Freeform Metis is a fact/token regurgitator. Loading symbols only enlarges the bag. It does not assert, bind, prove, compose, or learn from successful acts.  
**Canonical failure:**

```
user: x = y
user: what is y
today:   y = x   (or random domain-def bullets / unknown)
wanted:  y = x as *derived binding* from asserted equality (or value if x known)
         — via symbolic act + prove/solve, not string echo
```

**Related shipped work (keep; does not close this gap):**  
task-driven symbol activation (`symbol-task-*`), dual-facet law, seal load/dep pins, hybrid CLS loop, prove/unifier/RETE/TMS (exist but are not the freeform answer path).

---

## 1. Goal (what “completely satisfy” means)

Metis freeform / interactive turns must **use** loaded symbol knowledge as an active mind:

| Capability | Satisfied when |
|------------|----------------|
| **Assert** | NL statements become durable symbolic structure in the mind (bindings, equalities, facts), not chat history only |
| **Query** | NL questions become goals (`prove` / `ask` / process solve), not bag-of-tokens retrieval |
| **Compose** | Multiple facts + rules + process engines chain (session bindings + algebra rules + arithmetic) |
| **Explain** | Answer cites supporters (asserted facts, rules fired, process steps) — not “From loaded math symbols: • …” dumps |
| **Self-train only on success** | Hippocampus / consolidate / skill install after *accepted* solve/prove, not after regurgitate hits |
| **Symbol load still gated** | Task prepare remains working-set; loaded packs supply **rules/process**, not only printable defs |

**Hard product law (extends dual-facet):**  
Facts alone never count as “having” a domain. **Using** a math symbol means Process (and rules) can fire on goals. Knowledge facet answers *about* the domain only when the user asks *about* it — never as a substitute for solving.

---

## 2. Acceptance criteria (approval checklist)

### A. Equality / binding composition (user’s example)

1. After `x = y` (or `x equals y`, `let x = y`), mind holds a first-class binding/equality fact (not only a turn string).
2. `what is y` / `what's y?` / `solve for y` returns the bound form (`y = x` or value) via **prove/solve path**, with `:source` in `{ :prove, :solve, :bind }` — not `:math-knowledge` token dump.
3. If later `x = 2`, then `what is y` yields `2` (compose equality + value), with steps or supporters listing both assertions.
4. Unrelated `what is a limit?` still uses Knowledge facet (domain-def), not the binding engine.

### B. Multi-hop composition

5. At least one shipped path composes **≥2** independent supports (e.g. session equality + arithmetic, or two algebra rules) into one answer.
6. Loaded algebra/calculus **rules** (or process engines), not only `domain-def` strings, participate when relevant.

### C. Freeform routing

7. Freeform order: chitchat → **act/prove/solve** (new) → process math expr → extractive attachments → knowledge-about → …  
   Knowledge-about must **not** steal solve/query turns (no weak token match on CAPABILITY/DOMAIN for “what is y”).
8. Task prepare still runs before gated surfaces; cannot replace act/prove/solve.

### D. Self-training discipline

9. Successful prove/solve asserts episode + optional consolidate / skill only when gate accepts (reuse hybrid coupled accept ideas).
10. Pure retrieval answers (knowledge dump, extractive) do **not** mark “learned skill” for that query.

### E. Tests & honesty

11. In-repo FiveAM tests drive real entry points (`iface-turn` / freeform / cognitive path) with the equality scenario and multi-hop scenario — no mocks of the unit under test.
12. Docs (SYMBOL-FACETS or this plan’s successor) state: Knowledge = about; Process+prove = use; regurgitate is a bug if used as solve.

---

## 3. Non-goals

- Replacing sealed packages with a kitchen-sink LLM as the default reasoner  
- Perfect open-domain NL understanding (scope: equality, arithmetic, linear/simple algebra, explicit “what is X”, teach/assert patterns first)  
- Rewriting seal crypto / marketplace / task-load policy (reuse as working-set layer)  
- GPU / environment plugin auto-enable  
- Silent multi-pack thrash every turn  
- Claiming “AGI” or general self-awareness  

---

## 4. Architecture (target)

```
NL turn
  → task-prepare (working set)                    [already shipped]
  → NL act parser  →  Act IR
        |                 |
        |    :assert      |  :query / :solve
        v                 v
   mind assert-fact    goal builder
   (bindings, eqs)          |
                            v
              ┌─────────────┴──────────────┐
              │  Reasoner core (NEW glue)  │
              │  prove / rewrite / process  │
              │  using loaded symbol rules │
              │  + session WM + process    │
              └─────────────┬──────────────┘
                            v
              answer + supporters + steps
                            │
              success? ──yes──► hippocampus + optional consolidate
                   │
                   no ──► honest unknown / partial explain
```

### 4.1 Act IR (new small contract)

Uniform intermediate representation, plist or struct, e.g.:

```lisp
(:act :assert :kind :equality :lhs "x" :rhs "y" :raw "x = y")
(:act :query  :kind :value-of :var "y" :raw "what is y")
(:act :solve  :kind :expression :expr "2+2" ...)
(:act :about  :kind :definition :topic "limit" ...)  ; knowledge facet
(:act :unknown :raw "...")
```

Parser is **heuristic + tight patterns** first (equality, `what is`, `solve for`, bare expr). Expand later; do not block on full NLU.

### 4.2 Session / mind binding store

- Prefer first-class facts already native to Metis: e.g. `(= x y)`, `(binds y x)`, `(value x 2)` — pick one canonical form and stick to it.
- Assert via existing `assert-fact` / `tell` with support `:user-turn` or `:session-bind`.
- Retract/replace policy: new assignment to `x` supersedes previous value (document + test).

### 4.3 Reasoner core (the missing middle)

New module (suggested name): `src/reason-act.lisp` or `src/symbols/use.lisp` — **glue only**, reuses:

| Existing | Role |
|----------|------|
| `prove` / `prove-query` / unifier | Goal satisfaction over KB |
| RETE / rules from packs | Forward chaining when packs ship rules |
| `%iface-math-answer` / process engines | Numeric / algebraic process facet |
| TMS | Optional integrity on learned path |
| `symbol-task-prepare!` | Ensure domain packs before reason |
| hybrid hippocampus / consolidate | Learn only on accepted success |

**Do not** implement a second prover. Wire freeform → goals → existing prove + process.

### 4.4 Answer contract

Every act/prove/solve answer:

```lisp
(:freeform :reasoned
 :reply-text "y = x"
 :source :prove          ; or :solve :bind
 :supporters ((:= x y) ...)
 :steps (("from" (= x y)) ("therefore" (= y x)))
 :learned nil)           ; or metrics if consolidate ran
```

Knowledge-about remains:

```lisp
(:freeform :math-knowledge :reply-text "…" :source :math-knowledge :facet :knowledge)
```

### 4.5 Freeform pipeline (new order)

```
0  task-prepare
1  chitchat / identity (NL use)
2  **reason-act** (assert | prove | solve)     ← NEW primary product path
3  process math (bare expression eval)
4  extractive attachments
5  local-user
6  knowledge-about (math-know, nl-about, concept)  ← only for about-questions
7  KB / LLM / refuse / unknown
```

### 4.6 Self-training rules

| Event | Encode episode? | Consolidate / skill? |
|-------|-----------------|----------------------|
| Successful prove/solve with supporters | yes (`:source :reasoned`) | yes if `learn :auto` / policy |
| Assert only | yes (light) | no |
| Knowledge dump / extractive | optional | **no** |
| Failed prove | yes (`:success nil`) | no |

Reuse `hybrid-coupled-accept-p` / TMS ideas: never “learn” from regurgitate.

---

## 5. Implementation phases (approveable DAG)

### Phase 0 — Product contract & fixtures (docs + tests skeleton)

- Land this plan as approved (`Status: APPROVED` + date).
- Extend SYMBOL-FACETS: Knowledge ≠ Use; Use for math = Process + prove over session state.
- Skeleton suite `:metis-reason-act` with failing tests for acceptance A1–A3 (TDD).

**Done when:** tests fail for the right reasons; docs state the law.

### Phase 1 — Act parser + assert path

- `parse-reason-act` (or equivalent) for:
  - equality: `x = y`, `x equals y`, `let x be y`
  - assignment with value: `x = 2`, `set x to 2`
  - query: `what is y`, `what's y`, `value of y`
- Assert path writes canonical facts into mind.
- Freeform: on `:assert`, reply confirmation (“Noted: x = y”) + optional show binding.

**Done when:** `iface-turn` after `x = y` → fact visible via `ask`/`facts`; test A1 green.

### Phase 2 — Query path: prove/bind over session equalities

- Goal builder: `what is y` → prove `(= y ?v)` or chase binding chain.
- Symmetric equality: `(= x y)` implies `(= y x)` (rule or chase).
- Value chase: if `x` has value, substitute.
- Freeform returns `:source :prove` / `:bind` with supporters.

**Done when:** A2–A3 green end-to-end on `iface-turn`.

### Phase 3 — Process composition

- Bare expr still uses process engine.
- Worded solve: `if x = 2 and y = x what is y` → multi-assert + query in one turn **or** multi-clause parse.
- Algebra process hooks when algebra symbol loaded (linear solve minimal).

**Done when:** A5 multi-hop test green; process still works for `2+2`.

### Phase 4 — Symbol rules participation

- Ensure sealed/open packs that ship **rules** (not only domain-def) are loaded into the same KB prove sees.
- Audit algebra/math packs: if rules empty, add **minimal** rule seed for equality/symmetry/substitution (source-kit + train/seal only if needed; prefer open pack facts/rules first).
- Prove path prefers rules + session facts over domain-def string search.

**Done when:** A6 — a rule from a loaded symbol appears in supporters for at least one test.

### Phase 5 — Freeform reorder + anti-regurgitate guards

- Insert reason-act before math-know; restrict math-know to **about** questions (what is a *limit*, definition of …).
- Stopwords / about-classifier already partial — extend so `what is y` never hits domain-def bag.
- Preserve extractive attachment priority for document Q&A (regression suite already has penguin/otter).

**Done when:** A4, A7; iface extractive tests still pass.

### Phase 6 — Learn-on-success

- On reasoned success: `hippocampus-encode!` + optional `neocortex-consolidate!` under same policy as hybrid.
- Optional: install micro-skill “binding chase” after N successes (keep tiny).
- Metrics: `:reasoned-count`, `:regurgitate-blocked-count` for honesty.

**Done when:** A9–A10 tests (learn flag true only on reasoned success).

### Phase 7 — Polish & product surfaces

- TUI/status: show active bindings (short).
- `/bindings` or symbols pane session layer.
- CHANGELOG / release memo when shipping a version bump (separate release workflow).

---

## 6. File / module map (expected touch set)

| Area | Files (approx.) |
|------|------------------|
| Act parse + reason glue | **new** `src/reason-act.lisp` (or `src/symbols/use.lisp`) |
| Freeform order | `src/interface.lisp` |
| Math-know about-only | `src/symbols/runtime.lisp` |
| Exports | `src/package.lisp` |
| ASD | `metis.asd` |
| Hybrid learn hook | `src/hybrid.lisp` (light) |
| Tests | **new** `tests/reason-act.lisp`; keep `tests/task-load.lisp`, `tests/interface.lisp` |
| Docs | this plan; `docs/SYMBOL-FACETS.md`; optional `docs/REASON-ACT.md` |
| Packs (only if rules missing) | `knowledge/packs/math`, algebra source-kit — minimal rules |

No second seal stack. No second prover.

---

## 7. Verification plan (must pass before claim done)

1. **A-equality:** boot → freeform `x = y` → `what is y` → reply derives `y = x` (or equivalent), `:source` reasoned/prove/bind; facts contain equality. Log reply + fact list.  
2. **A-value:** `x = 2` → `y = x` → `what is y` → `2` with multi supporters.  
3. **A-about:** `what is a limit?` (with calculus loaded) → knowledge path, not binding.  
4. **A-anti-regurg:** `what is y` with empty bindings → honest unknown / ask for binding — **not** random domain-def bullets containing letter y.  
5. **A-extractive regression:** attach penguin doc → `tell me about penguins` still extractive.  
6. **A-learn:** reasoned success sets learn/episode; knowledge dump does not claim skill learn.  
7. **Suite:** `:metis-reason-act` + `:metis-iface` + `:metis-task-load` + `:metis-hybrid` PASS.  
8. **Evidence:** grep shows freeform calls reason-act before math-know; reason-act calls `prove`/`assert-fact` (not reimplemented search).

---

## 8. Risks & decisions (need explicit stance on approve)

| Risk | Mitigation / decision |
|------|------------------------|
| NL parse too weak | Phase 1 patterns only; expand with tests; never pretend full NLU |
| Equality in KB vs process engine | Canonical fact form + chase; process for arithmetic only |
| Packs have defs not rules | Phase 4 minimal rule seeds; dual-facet Process already required for math |
| Learn noise | Learn-on-success only (Phase 6) |
| Scope creep into LLM | Default reasoner stays symbolic; LLM remains last-resort freeform |
| Task-load thrash | Keep pins; reason-act does not unload mid-prove |

**Approval choices (fill on approve):**

- [ ] Canonical equality form: `(= a b)` vs `(binds a b)` — **recommend `(= a b)` + symmetry rule**  
- [ ] Multi-clause single turn (`if x=2 and y=x what is y`) in Phase 3 vs multi-turn only first — **recommend Phase 3 single-turn for the demo sentence**  
- [ ] Version bump target after Phase 6 — e.g. 4.6 USE — **recommend yes, separate release workflow**

---

## 9. Success demo script (human)

```
> x = y
Noted: x = y

> what is y
y = x
(supporters: (= x y); source: prove)

> x = 2
Noted: x = 2

> what is y
2
(supporters: (= x y), (= x 2) or value chase; source: prove)

> what is a derivative?
… knowledge from calculus symbol (about) …

> 2+2
4
(process)
```

If any line falls back to “From loaded math symbols: • DOMAIN-DEF …” for a solve/query, the gap is **not** closed.

---

## 10. Effort sketch (order of magnitude)

| Phase | Effort |
|-------|--------|
| 0 contract + failing tests | S |
| 1 parser + assert | M |
| 2 query/prove chase | M–L |
| 3 process composition | M |
| 4 symbol rules | M (depends on pack contents) |
| 5 freeform guards | S–M |
| 6 learn-on-success | S–M |
| 7 polish | S |

Total: roughly one focused product arc, not a research rewrite — **if** scope stays equality + simple composition first.

---

## 11. Approval block

**I approve this plan for implementation:**

- Name: _______________________  
- Date: _______________________  
- Options chosen (canonical form / single-turn multi-clause / version target):  
  ________________________________________________  
- Notes / cuts: ________________________________________________  

**On approve:** set `Status: APPROVED`, implement Phase 0→6 in order, do not ship “more facts” as a substitute for reason-act.

---

## 12. One-line thesis

**Stop answering questions by searching strings inside loaded packs. Assert what the user teaches; prove and solve with the mind and symbol process/rules; only then speak — and only train on that success.**
