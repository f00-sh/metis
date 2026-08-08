# Metis Symbol Training Guide (DETAILED)

**Audience:** researchers, students, labs, and independent authors who want to
**create, train, seal, publish, and load** knowledge symbols for Metis.

**Product doctrine (one line):**  
Metis is an empty, unguarded runtime. Symbols are owner-controlled, sealed,
pre-trained knowledge packages. Metis does **not** censor symbol content.
Engineering checks only (hash, signature, decrypt, dependencies).

**Honest security claim:**  
Sealed symbols are **opaque and tamper-evident at rest**. Casual open/edit/`strings`
on the body fails. Bit-flips fail verify and load is refused.  
We do **not** claim perfect unextractability against a hostile reverse-engineer
who can run the symbol under a debugger on their own machine.

---

## 0. Concepts in plain language

| Term | Meaning |
|------|---------|
| **Source kit** | Your readable kitchen: manifests, bibliography, facts, corpus text |
| **Train / build** | Metis digests the kit into structured knowledge (+ optional LM epochs) |
| **Sealed package** | Shipped form: public **header** + opaque **body** + **signature** |
| **open-sealed** | Opaque body, but key derivation is **documented** so anyone can rebuild the same package from the same sources (science / open knowledge) |
| **private-sealed** | Opaque body encrypted with **your passphrase/key**; only key holders can load |
| **Fingerprint (SHA-256)** | Unique id of the bytes; used to detect tampering |
| **Signature** | Proves the package was sealed with a known trust key |
| **Marketplace index** | Free open catalog of published id/version/hash/trust-tier (no payments) |
| **Sideload** | Install from USB/path not from catalog → always treated carefully; mark **UNVETTED** |
| **local-user** | Separate live layer of what *you* taught *this* mind (not a published symbol) |

**You do not ship a folder of PDFs.**  
You ship a **trained, sealed package**. PDFs/notes stay in the source kit (or as citations).

---

## 0b. TUI keys (product surface)

When the TUI is running, **Ctrl chords are hijacked by Metis** (raw tty:
no IXON, no ISIG). If a host still eats a chord, backups exist.

| Action | Keys |
|--------|------|
| Chat ↔ **symbols pane** | **Ctrl+T** · **F2** · type `/symbols` |
| REPL popup | **Ctrl+R** · **F3** · `/repl` |
| Settings popup | **Ctrl+S** · **F4** · `/settings` |
| Newline in input | **Ctrl+N** |
| Quit | `/quit` · Ctrl+C |

Restart Metis after upgrades so key-rev in the banner increments (proves fresh code).

## 1. Install prerequisites

```bash
# From the Metis repo root
cd /path/to/metis
# SBCL + Quicklisp assumed (see docs/install.md)
./bin/metis test          # sanity: system loads
./bin/metis symbol help   # this CLI
```

Trust key for local signing (auto-created on first seal):

```text
~/.metis/trust/keys.lisp   ; includes metis-dev for development
```

Change the `metis-dev` secret before publishing anything you care about.

---

## 2. Source kit layout

Create a kit:

```bash
./bin/metis symbol new my-domain
# → knowledge/source-kits/my-domain/
```

Resulting tree:

```text
knowledge/source-kits/my-domain/
  source-manifest.lisp   ; id, version, license, deps, capabilities, category
  bibliography.lisp      ; citations (title, URL/DOI, license, date)
  facts.lisp             ; curated symbolic facts  (:facts (...))
  rules.lisp             ; optional rules          (:rules (...))
  corpus/                ; plain .txt training prose (license-clear only)
  sources/               ; optional raw downloads you cite (not shipped in body)
  trained-facts.lisp     ; written by train step (snapshot)
```

### 2.1 `source-manifest.lisp` (example)

```lisp
(:metis-source-kit 1
 :id "my-domain"
 :name "My Domain"
 :version "1.0.0"
 :description "What this symbol teaches Metis"
 :license "CC-BY-4.0"
 :category :science
 :depends-on ((:id "math" :version ">=1.0.0" :role :required))
 :capabilities (:my-domain :science)
 :bibliography nil)
```

### 2.2 Bibliography entries (required for science-grade packs)

Each entry should include as many of these as you have:

| Field | Example |
|-------|---------|
| `:title` | "OpenStax College Algebra" |
| `:url` | "https://openstax.org/details/books/college-algebra" |
| `:doi` | optional |
| `:license` | "CC-BY-4.0" |
| `:date` | "2024" |
| `:note` | "Used for definition excerpts; not a full book dump" |
| `:content-hash` | SHA-256 of a local source file if you keep one under `sources/` |

### 2.3 Facts

Facts are Lisp lists. Prefer stable predicates:

```lisp
(:facts
 ((domain-def "algebra" "polynomial" "sum of terms a_i x^i")
  (domain-identity "algebra" "difference-of-squares"
                   "a^2 - b^2 = (a-b)(a+b)")
  (capability algebra "symbolic algebra facts")))
```

### 2.4 Corpus hygiene

- Prefer **CC-BY, CC0, public domain, university open course** material.
- Do **not** dump pirated commercial textbooks into the repo.
- **Book-scale is expected.** A real calculus/language symbol is *large*
  (full open textbooks / course notes), not ~20 hand facts.
- Short `term: definition` lines still help fact extraction; **entire chapters**
  go in via `symbol ingest-book`.
- One concept per line is optional for extraction:
  `polynomial: expression that is a sum of terms a_i x^i`

### 2.5 Book-scale ingest (entire open books)

```bash
# Convert PDF → text yourself (pdftotext) when the vendor allows, e.g. OpenStax CC-BY
pdftotext -layout OpenStax-Calculus-Volume-1.pdf calculus-vol1.txt

./bin/metis symbol ingest-book knowledge/source-kits/calculus \
  ./calculus-vol1.txt --chunk 12000

./bin/metis symbol train knowledge/source-kits/calculus
./bin/metis symbol build knowledge/source-kits/calculus
./bin/metis symbol verify knowledge/sealed/calculus
```

**Solving equations** is **not** “more facts.” Facts/corpus answer *what is*
and *explain*. **Process engines** (PEMDAS / algebra / future CAS hooks gated by
the math symbol capability) **compute**. A full calculus symbol needs **both**:
huge open curriculum text **and** the math process surface enabled.

---

## 3. Ingest corpus files

```bash
./bin/metis symbol ingest knowledge/source-kits/my-domain \
  /path/to/notes.txt \
  /path/to/more-open-notes.txt
```

Files are copied into `corpus/`.

---

## 4. Train (digest knowledge)

```bash
./bin/metis symbol train knowledge/source-kits/my-domain
```

What training does today (pure Common Lisp path):

1. Reads manifest, bibliography, facts, rules, corpus  
2. Optionally extracts `domain-def` facts from `term: definition` lines  
3. Records a `symbol-trained` event fact  
4. Optionally runs neural epochs if you call the Lisp API with `:epochs N`  
5. Writes `trained-facts.lisp` snapshot  

Lisp API:

```lisp
(metis:symbol-train-from-kit! "knowledge/source-kits/my-domain"
                              :extract-defs t
                              :epochs 0)  ; set >0 only if an LM is registered
```

**Training is not “upload to a giant cloud model.”**  
It is **building Metis-native knowledge** from your kit.

---

## 5. Seal (produce the shipped package)

### 5.1 Open-sealed (default — open knowledge, still opaque)

```bash
./bin/metis symbol build knowledge/source-kits/my-domain
# → knowledge/sealed/my-domain/
#    header.lisp   (public)
#    body.mse      (opaque encrypted body)
#    symbol.sig    (HMAC signature)
```

### 5.2 Private-sealed (creator key required to load)

```bash
./bin/metis symbol build knowledge/source-kits/my-domain \
  --private --key 'your-long-passphrase' \
  --trust unvetted
```

### 5.3 Trust tiers (labels, not content filters)

| Tier | Typical use |
|------|-------------|
| `core` | Shipped with Metis |
| `vetted` | Passed review / curator process |
| `org` | Signed/claimed by a known organization |
| `community` | Published free catalog, not fully reviewed |
| `unvetted` | Sideload / private / experimental — **always mark clearly** |
| `local` | local-user style live knowledge |

**Sideloaded packages must never pretend to be `core`.**

---

## 6. Verify (always)

```bash
./bin/metis symbol verify knowledge/sealed/my-domain
# exit 0 and :OK T on success
```

Checks:

- header schema  
- body SHA-256 matches header  
- `symbol.sig` HMAC over header+body digests  
- trust key present in `~/.metis/trust/keys.lisp`  

**Any failure → do not load.**

Tamper test (don’t do this on real packs): flip one byte in `body.mse` → verify fails.

---

## 7. Load / unload

```bash
./bin/metis symbol load knowledge/sealed/my-domain
# private:
./bin/metis symbol load knowledge/sealed/my-domain --key 'your-long-passphrase'
```

Lisp:

```lisp
(metis:boot)
(metis:symbol-seal-load! "knowledge/sealed/my-domain")
;; later
(metis:symbol-pack-disable! "my-domain")
```

Load path: **verify → decrypt → inject facts/rules via pack layers**.  
Unload/disable retracts layer-owned facts (refcount-safe with base pins).

---

## 8. Marketplace (free, no accounts/payments)

Local open index:

```text
knowledge/marketplace/index.lisp
```

On `symbol build`, Metis registers id/version/body-sha256/trust-tier.

Check a package against the index:

```bash
./bin/metis symbol marketplace-check my-domain 1.0.0 <body-sha256>
```

| Status | Meaning |
|--------|---------|
| `:match` | Same version + same hash as published |
| `:hash-mismatch` | Same version but different bytes → **corrupt or counterfeit** |
| `:newer-available` | A newer version is in the index |
| `:unknown` | Not in index (sideload / private) |

Sideload policy:

1. Still verify internal signature/hash  
2. If id known and hash differs → hard warning / refuse for enable of process symbols  
3. Trust badge stays **UNVETTED** unless a real vetting path promotes it  

---

## 9. Dependencies

Declare in the source manifest:

```lisp
:depends-on ((:id "math" :version ">=1.0.0" :role :required)
             (:id "algebra" :version ">=1.0.0" :role :required))
```

Examples:

- `algebra` → requires `math`  
- `calculus` → requires `algebra` (and typically trigonometry)  
- Domain history packs may soft-depend on `natural-language`  

**Rule of thumb:** process stacks form a DAG. No cycles.

**Load behavior (shipped):** `symbol-seal-load!` / `./bin/metis symbol load`  
reads `:depends-on` with `:role :required` and:

1. If the dep is already loaded → continue  
2. Else if `knowledge/sealed/<dep-id>/` exists → **auto-load** it first  
3. Else → **refuse** with an error listing missing deps  

Unload does not auto-cascade; disable dependents first if you need a clean tree.

---

## 10. Minimal end-to-end recipe (copy/paste)

```bash
cd /path/to/metis

# 1) new kit
./bin/metis symbol new demo-hello

# 2) add a fact + corpus line
#    edit knowledge/source-kits/demo-hello/facts.lisp and corpus/*.txt

# 3) train
./bin/metis symbol train knowledge/source-kits/demo-hello

# 4) seal (open)
./bin/metis symbol build knowledge/source-kits/demo-hello --trust community

# 5) verify
./bin/metis symbol verify knowledge/sealed/demo-hello

# 6) load into a mind
./bin/metis symbol load knowledge/sealed/demo-hello
```

Expected: verify `:OK T`; load reports facts injected; body.mse has no readable corpus strings.

---

## 11. Author checklist before “shipping”

- [ ] License on the pack is explicit and correct  
- [ ] Bibliography has real titles/URLs/licenses  
- [ ] No illegal full textbook dumps  
- [ ] `symbol train` completed; `trained-facts.lisp` looks sane  
- [ ] `symbol build` produced sealed dir  
- [ ] `symbol verify` passes  
- [ ] Opacity smoke: `strings body.mse` does not show corpus secrets  
- [ ] Deps declared and tested load order  
- [ ] Trust tier honest (`unvetted` if sideload/private)  
- [ ] Marketplace index updated if publishing  
- [ ] Version bumped for every content change (never edit a sealed body in place)

---

## 12. What “edit a symbol” means

**You never hex-edit a sealed package to “fix a fact.”**

Correct flow:

1. Edit the **source kit**  
2. `symbol train`  
3. Bump `:version`  
4. `symbol build` again  
5. New fingerprint + new marketplace entry  

The old sealed package remains a historical immutable artifact.

---

## 13. Lisp API map (shipped entry points)

| Function | Role |
|----------|------|
| `symbol-source-kit-new!` | Scaffold kit |
| `symbol-source-kit-ingest!` | Copy corpus files |
| `symbol-source-kit-read` | Read kit → plist |
| `symbol-train-from-kit!` | Train/digest |
| `symbol-build!` | Train + seal + marketplace register |
| `symbol-seal!` | Seal only |
| `symbol-seal-verify` | Integrity + authenticity |
| `symbol-seal-load!` | Verify + decrypt + inject |
| `symbol-seal-body-opaque-p` | Opacity probe for tests |
| `symbol-marketplace-check` | Catalog advisory |

CLI: `./bin/metis symbol …` → `./bin/symbol`.

---

## 14. Five shipped math domain kits (this repo)

Under `knowledge/source-kits/`:

| Id | Role | Depends on (declared) |
|----|------|------------------------|
| `math` | Arithmetic / number sense / PEMDAS concepts | — |
| `algebra` | Polynomials, equations, identities | `math` |
| `geometry` | Euclidean geometry basics | `math` |
| `trigonometry` | Trig functions & identities | `geometry`, `algebra` |
| `calculus` | Limits, derivatives, integrals (concepts) | `algebra`, `trigonometry` |

Sealed outputs: `knowledge/sealed/<id>/`.  
Sources are **license-clear open educational materials** (OpenStax, MIT OCW, public-domain references) cited in each kit’s bibliography — not pirated commercial textbooks.

---

## 15. Publishing (free marketplace)

Today (in-tree open index):

1. Build open-sealed package  
2. Ensure `knowledge/marketplace/index.lisp` lists id/version/hash  
3. Commit source kit + sealed package + index  
4. Push to GitHub  

Future: remote catalog URL fetch — same schema, still **no payments**.

Vetting path (process, not code censorship):

1. Community publish → `community`  
2. Review (hash, license, smoke load, provenance) → `vetted`  
3. Org signature / known key → `org`  

---

## 16. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `unknown trust key-id` | Run a seal once or create `~/.metis/trust/keys.lisp` |
| `body hash mismatch` | Package tampered or partial copy — re-download/rebuild |
| `decrypt failed` | Wrong private key, or open-sealed id/version mismatch |
| `signature mismatch` | Tamper or wrong key store |
| Facts missing after load | Verify returned ok? Correct id? Disabled layer? |

---

*End of training guide. For architecture notes see `docs/SYMBOL-DOCTRINE.md`.*
