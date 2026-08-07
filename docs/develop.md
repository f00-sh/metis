# Metis — Develop & extend

## Layout

```
src/           kernel, nn, symbols core
symbols/       first-class plugins (cpu-nn, gpu-nn, chat-ui, …)
knowledge/     bootstrap domains
tests/         FiveAM suites
docs/          overview · install · develop (this triad)
packaging/     image build helpers
bin/           launchers
```

## Writing a symbol

Create `symbols/my-cap/manifest.lisp`:

```lisp
(in-package :cl-user)
(metis.symbols:register-symbol!
 :id "my-cap"
 :name "My Capability"
 :version "0.1.0"
 :description "…"
 :capabilities '(:tool :iface)  ; or :nn-backend, :domain, :train, …
 :priority 40
 :path *default-pathname-defaults*
 :hooks (metis.symbols:define-symbol-hooks
          :activate (lambda (rec) … t)
          :deactivate (lambda (rec) t)))
```

Optional `symbol.lisp` loads after the manifest. Sign for remote install:

```lisp
(metis:sign-symbol-package #P"symbols/my-cap/")
```

## NN backend protocol

Backends implement:

- `nn-backend-matmul`
- `nn-backend-axpy`
- `nn-backend-relu`
- status/id/device

`t-matmul` / `t-relu` dispatch forward work through the **active** backend (`cpu-nn` or `gpu-nn`). Op counts prove train uses the GPU path when enabled.

## LM knobs (4.2 defaults)

- `:depth` default **3**
- `:seq-len` default **128**
- Train history records `:backend` and `:op-counts`

## Tests

```bash
./bin/metis test
# suites: core production bench further epoch iface nn symbols frontiers
```

## Extension principles

- Do not fork the kernel for product features — ship a **symbol**.
- Keep Decision B: pure CL default train/infer; GPU is enableable acceleration.
- Gate neural fire through TMS (`nn-path-enabled`).
