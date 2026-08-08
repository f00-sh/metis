# SOP — Metis release / packaging bump

**Version:** 4.5.0  
**Audience:** maintainers

## Purpose

Ship a versioned Metis release with consistent install channels.

## Preconditions

- Clean working tree on the release branch  
- Write access to GitHub `f00-sh/metis` and, for full channel push, homebrew-tap / aur-metis  

## Steps

1. **Bump version surfaces** to `X.Y.Z` (keep identical):  
   - `VERSION`  
   - `src/version.lisp`  
   - `metis.asd` `:version`  
   - `packaging/homebrew/metis.rb`  
   - `packaging/aur/PKGBUILD`  
   - README / site / man / docs triad version claims  

2. **CHANGELOG** — move Unreleased notes into `## X.Y.Z — …`  

3. **Docs pack** — README, `docs/*`, `site/`, `man/metis.1`, `file_id.diz` consistent  

4. **Tests** — `./bin/metis test` green  

5. **Tag & release**  
   ```bash
   git tag -a vX.Y.Z -m "Metis X.Y.Z"
   git push origin main --tags
   # GitHub Release: attach install.sh + metis-X.Y.Z-src.tar.gz
   git archive --format=tar.gz --prefix=metis-X.Y.Z/ -o /tmp/metis-X.Y.Z-src.tar.gz vX.Y.Z
   ```  

6. **Pin sha256** of the source tarball in formula + PKGBUILD; push.  

7. **Publish channels**  
   - Formula → `f00-sh/homebrew-tap` `Formula/metis.rb`  
   - PKGBUILD → `f00-sh/aur-metis`  

8. **Site** — if site copy changed, deploy per [sop-site-deploy.md](sop-site-deploy.md) (also auto on `site/**` push via `.github/workflows/pages.yml`).  

9. **Verify**  
   - `curl -fsSL https://metis.f00.sh/install.sh | head`  
   - `metis version` on a fresh install path when possible  
   - Live site shows **vX.Y.Z**  

## In-tree packaging notes

See [packaging/README.md](../packaging/README.md).
