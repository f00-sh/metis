# SOP — Deploy Metis site (metis.f00.sh)

**Version:** 4.5.0  
**Audience:** operators, CI  

## Purpose

Publish `site/` to Cloudflare Pages project **f00-metis** (https://metis.f00.sh/).

## Preconditions

- Wrangler auth: `CLOUDFLARE_API_TOKEN` + account (local) or GitHub secrets `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`  
- Working tree contains updated `site/` and `wrangler.toml`  

## Config

| Item | Value |
|------|--------|
| Project name | `f00-metis` |
| Output dir | `site` (`wrangler.toml` → `pages_build_output_dir`) |
| CI workflow | `.github/workflows/pages.yml` |

## A. Automatic deploy (preferred)

1. Commit changes under `site/**` (and/or `wrangler.toml`, workflow).  
2. Push to `main` (or `master`).  
3. GitHub Actions job **Deploy site (Cloudflare Pages)** runs:  
   `wrangler pages deploy site --project-name=f00-metis --branch=main`  
4. Confirm green workflow; wait for CDN.  

## B. Manual deploy (local)

```bash
cd /path/to/metis
# ensure site content is current
npx --yes wrangler pages deploy site --project-name=f00-metis --branch=main
# or: wrangler pages deploy site --project-name=f00-metis --branch=main
```

Env: API token with Pages edit permission.

## C. Post-deploy verify

1. `curl -fsSL -o /tmp/metis-live.html -w '%{http_code}\n' https://metis.f00.sh/` → **200**  
2. Body contains current version (e.g. `v4.5.0` or `4.5.0`).  
3. `curl -fsSL https://metis.f00.sh/install.sh | head -5` → installer banner.  

If version lags, re-fetch after ~30–60s or purge Pages cache in dashboard.

## D. Content checklist (before deploy)

- [ ] `site/index.html` version matches `VERSION`  
- [ ] Install block matches `docs/install.md`  
- [ ] Doc links point at live GitHub paths or reachable URLs  
- [ ] `site/install.sh` aligned with `scripts/install.sh`  

## Related

- [install.md](install.md)  
- [sop-release.md](sop-release.md)  
