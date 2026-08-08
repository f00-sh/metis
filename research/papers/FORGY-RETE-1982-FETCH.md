# Forgy RETE 1982 — fetch attempts (honest gap)

**Target:** Charles L. Forgy, “Rete: A Fast Algorithm for the Many Pattern/Many Object Pattern Match Problem,” *Artificial Intelligence* 19 (1982).

**Local PDF:** not present (`forgy-rete-1982.pdf` not in tree).

## Attempted URLs (2026-08-07)

| URL | Result |
|-----|--------|
| https://www.cse.unsw.edu.au/~billw/cs9414/notes/kr/rules/forgy82.pdf | HTTP 403 |
| https://web.archive.org/web/20170829123101/http://www.cse.unsw.edu.au/~billw/cs9414/notes/kr/rules/forgy82.pdf | HTTP 429 |
| https://cis.temple.edu/~giorgio/cis587/readings/RETE.pdf | HTTP 404 |
| https://www.cs.cmu.edu/afs/cs/project/ai-repository/ai/areas/expert/systems/ops5/rete.ps | HTTP 404 |
| https://arxiv.org/pdf/not-a-real-forgy.pdf | HTTP 404 (probe) |

Full curl log: goal scratch `forgy-fetch.log`.

**Product status:** Metis implements RETE in `src/rete.lisp` regardless; gap is bibliographic PDF only.
