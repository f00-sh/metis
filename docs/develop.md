# Metis — Develop & extend

**Version: 4.5.0**

## Layout

```
src/              kernel, nn/, symbols/, chat-spine, reason-act, interface
symbols/          first-class plugins (cpu-nn, gpu-nn, …)
knowledge/        source-kits/, sealed/, packs/, bootstrap
tests/            FiveAM suites (iface, nn, seals, reason-act, chat-spine, …)
docs/             overview · install · develop · SYMBOL-* · SOPs
site/             Cloudflare Pages root (metis.f00.sh)
packaging/        Homebrew + AUR helpers
bin/              launchers
man/metis.1       man page
```

## Quick developer loop

```bash
./bin/metis version
./bin/metis test
# targeted:
sbcl --eval '(ql:quickload :metis/tests)' \
     --eval '(fiveam:run! :metis-chat-spine)' --quit
```

Suites include: core, production, iface, nn, symbols, packs, seals, task-load, reason-act, **chat-spine**, install, frontiers, hybrid.

## Writing a plugin symbol

Create `symbols/my-cap/manifest.lisp`:

```lisp
(in-package :cl-user)
(metis.symbols:register-symbol!
 :id "my-cap"
 :name "My Capability"
 :version "0.1.0"
 :description "…"
 :capabilities '(:tool :iface)
 :priority 40
 :path *default-pathname-defaults*
 :hooks (metis.symbols:define-symbol-hooks
          :activate (lambda (rec) t)
          :deactivate (lambda (rec) t)))
```

Sign for remote install:

```lisp
(metis:sign-symbol-package #P"symbols/my-cap/")
```

## Knowledge symbols (sealed)

See [SYMBOL-TRAINING.md](SYMBOL-TRAINING.md). Pipeline:

1. `metis symbol new <id>`  
2. Author facts/corpus in `knowledge/source-kits/<id>/`  
3. `metis symbol train` → `metis symbol build`  
4. `metis symbol verify` / `load`  

## House chat spine & model packages

| API | Role |
|-----|------|
| `house-chat-ensure!` | Train/register in-process house LM |
| `house-chat-generate` | Residual freeform mouth |
| `symbol-model-attach!` / `detach!` | Condition generation (adapter tags / weights metadata) |

Packs with `model.ckpt` or `:model-package` attach conditioners on enable.

## reason-act

Session equalities: `x = y`, `what is y`, multi-clause compose. Canonical facts `(= A B)`. Freeform runs reason-act **before** knowledge dumps.

## NN backend protocol

Backends implement matmul / axpy / relu. Active backend is `cpu-nn` or `gpu-nn`. TMS: `nn-enable-path` / `nn-disable-path`.

## Extension principles

1. Prefer a **symbol** over forking the kernel.  
2. Decision B: pure CL default; GPU is enableable.  
3. Gate neural fire through TMS.  
4. Product freeform never uses external LLM as the mind.  
5. Dual-facet law is hard (see [SYMBOL-FACETS.md](SYMBOL-FACETS.md)).

## Packaging

See [packaging/README.md](../packaging/README.md) and [sop-release.md](sop-release.md).
