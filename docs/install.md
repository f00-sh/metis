# Metis — Install & operations

## Requirements

- SBCL (tested 2.x) + Quicklisp
- Optional: NVIDIA driver + `libcuda.so` for `gpu-nn`
- Optional: `git`, `curl`, `openssl` for remote symbol install and signing
- No Python required for core train/infer

## Install

```bash
# from source
cd /path/to/metis
# ensure Quicklisp can see the system (symlink or local-projects)
ln -sfn "$(pwd)" ~/quicklisp/local-projects/metis
sbcl --eval '(ql:quickload :metis)' --quit
```

## Run

```bash
./bin/metis test
./bin/metis iface
./bin/metis repl
```

## GPU backend

```lisp
(metis:boot)
(metis:enable-symbol! "gpu-nn")   ; fails cleanly if no CUDA
(metis:nn-backend-status)
(metis:disable-symbol! "gpu-nn")  ; back to cpu-nn
```

Iface: `/symbols enable gpu-nn`, `/symbols backend`.

## Symbols install (local / remote / trust)

```lisp
;; local directory (unsigned OK by default)
(metis:install-symbol! "/path/to/my-symbol")

;; remote requires symbol.sig (HMAC over package digests)
(metis:sign-symbol-package "/path/to/my-symbol")  ; uses ~/.metis/trust/keys.lisp
(metis:install-symbol! "file:///path/to/my-symbol")
(metis:install-symbol! "https://example.com/pkg.tar.gz")  ; git/http also supported
```

Trust keys live in `~/.metis/trust/keys.lisp` as an alist of `(key-id . secret)`.
Unsigned remote packages are **refused**.

## Packaged image

```bash
./bin/package-metis
# produces build/metis.image — run with:
sbcl --core build/metis.image
```

## Ops notes

- Models/checkpoints: `models/` under the system tree (or `*nn-model-dir*`)
- User symbols: `~/.metis/symbols/`
- HTTP API default: `127.0.0.1:7433` when started
