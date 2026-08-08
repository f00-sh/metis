# Release memo — Metis 4.4.1 THEORY

**Date:** 2026-08-08  
**Tag:** `4.4.1`  
**HEAD line:** dual-facet sealed symbols + dependency pin unload on the 4.4 THEORY base.

## What shipped

1. **Dep unload contract** — shared pins stay; auto-deps cascade on last pin; explicit loads sticky.
2. **Dual-facet law** — math knowledge+process; language use+about; default single-facet knowledge for other domains.
3. **Seals + train path** — open/private sealed packages; five math domain symbols; free marketplace index.
4. **f00 universe** — `https://metis.f00.sh/`, first card on `https://f00.sh/`, canonical repo `f00-sh/metis`.

## Verify

```bash
./bin/metis test   # or: sbcl --load bin/run-tests.lisp
# seals alone: (fiveam:run! :metis-seals)  → 121 checks
```

## Honesty

Opaque + tamper-evident seals at rest; **not** perfect anti-RE DRM.
