# Release memo — Metis 4.5.0 THEORY

**Date:** 2026-08-08  
**Tag:** `4.5.0`  
**Focus:** Install channels (curl/.sh, Homebrew, AUR) + regression of dual-facet/dep-pin line.

## What shipped

1. **`scripts/install.sh` / `site/install.sh`** — prefix install of product tree + launcher + man.
2. **Homebrew** — `packaging/homebrew/metis.rb` on `f00-sh/homebrew-tap`.
3. **AUR-style** — `packaging/aur/PKGBUILD` on `f00-sh/aur-metis`.
4. **`metis version`**, `METIS_ROOT`, docs/site install panel.

## Verify

```bash
PREFIX=/tmp/metis-prefix ./scripts/install.sh
/tmp/metis-prefix/bin/metis version
sbcl --load bin/run-tests.lisp
```
