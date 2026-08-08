# Metis packaging

Metis is a **Common Lisp source product** (SBCL + Quicklisp), not a single static binary.

## Channels

| Channel | Path | User command |
|---------|------|----------------|
| Curl / shell | `scripts/install.sh` · `site/install.sh` | `curl -fsSL https://metis.f00.sh/install.sh \| bash` |
| Homebrew | `packaging/homebrew/metis.rb` → `f00-sh/homebrew-tap` | `brew install f00-sh/tap/metis` |
| AUR-style | `packaging/aur/PKGBUILD` → `f00-sh/aur-metis` | `makepkg -si` / AUR helper when published |

## Layout after install

```
$PREFIX/bin/metis              # launcher
$PREFIX/share/metis/           # product tree (METIS_ROOT)
$PREFIX/share/man/man1/metis.1
```

Homebrew uses `libexec` for the tree; AUR uses `/usr/lib/metis`.

## Release bump checklist

1. Bump `VERSION`, `src/version.lisp`, `metis.asd`, formula `version`/`url`, PKGBUILD `pkgver`.
2. Tag + GitHub Release (attach `install.sh` asset for curl from releases).
3. `sha256sum` of `https://github.com/f00-sh/metis/archive/refs/tags/$VER.tar.gz` → formula + PKGBUILD.
4. Push formula to `f00-sh/homebrew-tap` `Formula/metis.rb`.
5. Push PKGBUILD to `f00-sh/aur-metis` (org-keyed AUR mirror).
