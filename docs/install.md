# Metis — Install & operations

## Requirements

- **SBCL** 2.x + **Quicklisp** (runtime)
- Optional: `git`, `curl`, `openssl` for remote symbol install and sealing
- Optional: NVIDIA driver + `libcuda.so` for `gpu-nn` symbol
- No Python required for core train/infer

## Install methods

### 1) Curl / shell (recommended)

```bash
curl -fsSL https://metis.f00.sh/install.sh | bash
# pin:
curl -fsSL https://metis.f00.sh/install.sh | METIS_VERSION=4.5.0 bash
```

Default prefix: `~/.local`  
Launcher: `~/.local/bin/metis`  
Tree: `~/.local/share/metis` (`METIS_ROOT`)  
Man: `~/.local/share/man/man1/metis.1`

From a git checkout (local tree, no network):

```bash
./scripts/install.sh
PREFIX=/opt/metis ./scripts/install.sh
```

### 2) Homebrew (f00-sh tap)

```bash
brew install f00-sh/tap/metis
metis version
```

Formula source in-tree: `packaging/homebrew/metis.rb` (published to
[f00-sh/homebrew-tap](https://github.com/f00-sh/homebrew-tap)).

### 3) AUR-style PKGBUILD

In-tree: `packaging/aur/PKGBUILD`  
Org-keyed mirror: [f00-sh/aur-metis](https://github.com/f00-sh/aur-metis)

```bash
# from packaging/aur
makepkg -si
# or clone the keyed AUR mirror when published
```

Depends on `sbcl`. Metis is **arch=any** source layout under `/usr/lib/metis`.

### 4) From source (developer)

```bash
git clone https://github.com/f00-sh/metis.git
cd metis
ln -sfn "$(pwd)" ~/quicklisp/local-projects/metis
./bin/metis version
./bin/metis test
```

## Run

```bash
metis                 # TUI (default)
metis chat            # line interface
metis version
metis test
metis symbol help
```

## GPU backend

```lisp
(metis:boot)
(metis:enable-symbol! "gpu-nn")   ; fails cleanly if no CUDA
(metis:nn-backend-status)
```

## Symbols install (local / remote / trust)

See `docs/SYMBOL-TRAINING.md`. Trust keys: `~/.metis/trust/keys.lisp`.

## Packaged SBCL image (optional)

```bash
./bin/package-metis
# build/metis.image — sbcl --core build/metis.image
```

## Ops notes

- User data / packs: `~/.metis/`
- Models: `models/` under the package tree
- HTTP API default: `127.0.0.1:7433` when started
