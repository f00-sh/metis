# SOP — Metis day-to-day operations

**Version:** 4.5.0  
**Audience:** operators, release engineers, agents

## Purpose

Run, smoke-test, and recover a Metis install without inventing steps.

## Preconditions

- SBCL + Quicklisp available, or a prior successful `scripts/install.sh`  
- Network only if installing/updating from remote  

## A. Start of day — quality gates

1. Confirm version: `metis version` or `./bin/metis version` → matches `VERSION` (4.5.0).  
2. Optional full suite: `metis test` / `./bin/metis test`.  
3. Targeted after docs-only changes: `fiveam` install suite if present (`:metis-install`).  
4. Confirm site tree present if deploying: `ls site/index.html site/install.sh`.

## B. Run product

1. Interactive TUI: `metis`  
2. Line chat: `metis chat`  
3. Enable neural path in REPL/chat as needed: `/nn enable`  
4. Load domain: `metis symbol load knowledge/sealed/math` (full tree)  
5. Exit TUI: `/quit`  

## C. Failure recovery

| Symptom | Action |
|---------|--------|
| `metis: command not found` | Ensure `~/.local/bin` on PATH; re-run install |
| Quicklisp / ASDF missing system | `ln -sfn $METIS_ROOT ~/quicklisp/local-projects/metis` |
| Neural path refuse | `/nn enable` or `(metis:nn-enable-path)` |
| Symbol verify fail | Re-fetch seal; check `~/.metis/trust/keys.lisp` |
| Tests fail after pull | `./bin/metis test`; check SBCL version; clean fasls if needed |

## D. Data locations

- User: `~/.metis/`  
- Install tree: `$METIS_ROOT` (default `~/.local/share/metis`)  
- Models: `$METIS_ROOT/models/`  

## E. Cross-refs

- Install detail: [install.md](install.md)  
- Release: [sop-release.md](sop-release.md)  
- Site: [sop-site-deploy.md](sop-site-deploy.md)  
