# Metis packaging

**Product version:** see root `VERSION` (**4.5.0**).  
Metis is a **Common Lisp source product** (SBCL + Quicklisp), not a single static binary.

Full release SOP: [docs/sop-release.md](../docs/sop-release.md).  
Site deploy SOP: [docs/sop-site-deploy.md](../docs/sop-site-deploy.md).

## Channels

| Channel | Path | User command |
|---------|------|----------------|
| Curl / shell | `scripts/install.sh` · `site/install.sh` | `curl -fsSL https://metis.f00.sh/install.sh \| bash` |
| Homebrew | `packaging/homebrew/metis.rb` → `f00-sh/homebrew-tap` | `brew install f00-sh/tap/metis` |
| AUR-style | `packaging/aur/PKGBUILD` → `f00-sh/aur-metis` | `makepkg -si` |

## Layout after install

```
$PREFIX/bin/metis              # launcher
$PREFIX/share/metis/           # product tree (METIS_ROOT)
$PREFIX/share/man/man1/metis.1
```

Homebrew uses `libexec` for the tree; AUR uses `/usr/lib/metis`.

## Release assets

GitHub Release attaches:
- `install.sh`
- `metis-$VER-src.tar.gz` (source tree for brew/AUR; stable sha256)

## Bump checklist

1. Bump `VERSION`, `src/version.lisp`, `metis.asd`, formula/PKGBUILD versions.
2. Tag + GitHub Release; upload `install.sh` + `metis-$VER-src.tar.gz` from `git archive`.
3. Pin sha256 of that asset in formula + PKGBUILD; push main + retag if needed.
4. Push formula to `f00-sh/homebrew-tap` `Formula/metis.rb`.
5. Push PKGBUILD to `f00-sh/aur-metis`.
