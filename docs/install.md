# Metis — Install & operations (SOP)

**Version: 4.5.0** · Operator steps in STE-style order.

## 1. Requirements

| Need | Notes |
|------|--------|
| **SBCL** 2.x | Runtime |
| **Quicklisp** | Libraries |
| Optional `git`, `curl`, `openssl` | Remote symbols / seal verify |
| Optional NVIDIA + `libcuda.so` | `gpu-nn` symbol only |
| No Python | Core train/infer |

## 2. Install methods

### 2.1 Curl (recommended)

```bash
curl -fsSL https://metis.f00.sh/install.sh | bash
curl -fsSL https://metis.f00.sh/install.sh | METIS_VERSION=4.5.0 bash
```

| Item | Default |
|------|---------|
| Prefix | `~/.local` |
| Launcher | `~/.local/bin/metis` |
| Tree | `~/.local/share/metis` (`METIS_ROOT`) |
| Man | `~/.local/share/man/man1/metis.1` |

From a git checkout (no network download of the tree):

```bash
./scripts/install.sh
PREFIX=/opt/metis ./scripts/install.sh
```

In-repo installer: [`scripts/install.sh`](../scripts/install.sh)  
Site copy (must stay aligned): [`site/install.sh`](../site/install.sh)

### 2.2 Homebrew

```bash
brew install f00-sh/tap/metis
metis version
```

Formula: [`packaging/homebrew/metis.rb`](../packaging/homebrew/metis.rb) → [f00-sh/homebrew-tap](https://github.com/f00-sh/homebrew-tap).

### 2.3 AUR-style

```bash
# from packaging/aur
makepkg -si
```

In-tree: [`packaging/aur/PKGBUILD`](../packaging/aur/PKGBUILD) · mirror [f00-sh/aur-metis](https://github.com/f00-sh/aur-metis).

### 2.4 Source (developer)

```bash
git clone https://github.com/f00-sh/metis.git
cd metis
ln -sfn "$(pwd)" ~/quicklisp/local-projects/metis
./bin/metis version
./bin/metis test
```

## 3. Run

```bash
metis                 # TUI
metis chat            # line interface
metis version
metis test
metis symbol help
metis epoch
```

From checkout: prefix with `./bin/`.

## 4. Smoke (after install)

1. `metis version` → prints **4.5.0** (or current `VERSION`).  
2. `metis help` → lists chat / symbol / test.  
3. Optional: `metis test` (needs SBCL + QL deps).  
4. Optional: `metis symbol verify knowledge/sealed/math` from a full tree.

## 5. Neural path

```lisp
(metis:boot)
(metis:nn-enable-path)          ; TMS path IN
(metis:house-chat-ensure!)      ; residual freeform house LM
(metis:enable-symbol! "gpu-nn") ; only if CUDA present
```

## 6. Symbols

```bash
metis symbol load knowledge/sealed/calculus
```

Trust keys: `~/.metis/trust/keys.lisp`. Author guide: [SYMBOL-TRAINING.md](SYMBOL-TRAINING.md).

## 7. Packaged image (optional)

```bash
./bin/package-metis
# build/metis.image
```

## 8. Ops paths

| Path | Content |
|------|---------|
| `~/.metis/` | User packs, trust, keys |
| `$METIS_ROOT/models/` | In-process LM checkpoints |
| `127.0.0.1:7433` | HTTP API when started |

## 9. Related SOPs

- [sop-metis-ops.md](sop-metis-ops.md) — day-to-day gates  
- [sop-release.md](sop-release.md) — version bump & release assets  
- [sop-site-deploy.md](sop-site-deploy.md) — deploy metis.f00.sh  
