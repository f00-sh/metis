# Metis agents

## f00 membership

- Org: `f00-sh`
- Catalog SSOT: https://f00.sh/catalog.json
- Theme: https://f00.sh/theme/f00-theme.css
- Site: https://metis.f00.sh/
- Repo: https://github.com/f00-sh/metis

## Product facts (keep docs honest)

| Fact | Value |
|------|--------|
| Version | Read `VERSION` (4.5.0) — never invent a higher line without bumping |
| Runtime | SBCL + Quicklisp; pure-CL train/infer default |
| Site root | `site/` → Cloudflare Pages project `f00-metis` (`wrangler.toml`) |
| Freeform mind | House chat spine in-process; **no external LLM** as product freeform |
| Symbols | Sealed dual-facet packages + plugins; empty host runtime |

## When editing

1. User-visible behavior → update **README**, **docs triad** (`overview` / `install` / `develop`), **site/**, **man/metis.1** in the same change when claims change.  
2. Operator process change → update **docs/sop-*.md**.  
3. Symbol/facet law → **docs/SYMBOL-FACETS.md** (and training/doctrine if seal path changes).  
4. Deploy site: follow **docs/sop-site-deploy.md** (`npx wrangler pages deploy site --project-name=f00-metis` or CI `pages.yml`).  
5. Do not revive “4.2 FRONTIERS” / “4.4 THEORY” as the **current** version string.

## Tests

```bash
./bin/metis test
# or FiveAM suites: :metis-iface :metis-chat-spine :metis-reason-act :metis-seals …
```

## SOP index

- [docs/sop-metis-ops.md](docs/sop-metis-ops.md)  
- [docs/sop-release.md](docs/sop-release.md)  
- [docs/sop-site-deploy.md](docs/sop-site-deploy.md)  
- [docs/install.md](docs/install.md)  
