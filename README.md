# Engram

**Local-first associative memory for OpenClaw agents.** One command in, one
command out. Sharp recall, honest "I don't know", procedural methods, future
intentions, time-aware facts, and graph-walk retrieval — all on SQLite, no
cloud dependencies.

## What it does

Engram installs a persistent memory brain into any OpenClaw workspace:

- **Recall** — hybrid retrieval: FTS5 + semantic embeddings + tag/graph
  channels fused with weighted RRF, reranked by a small CPU cross-encoder.
- **Honesty** — calibrated abstention: when nothing is genuinely grounded,
  it says "no confident match" instead of confabulating.
- **Methods** — procedural memory: store how a task was done right, get it
  back the next time the task pattern comes up.
- **Intentions** — prospective memory: `engram intend "when X" "do Y"` and
  the reminder fires when the trigger appears in conversation context.
- **Time** — bi-temporal facts: `asof "query" --date 2024-06-01` answers
  what was true *then*; superseded facts are demoted, never hidden.
- **Migration** — parses your existing `MEMORY.md`, `memory/*.md`, and
  `AGENTS.md` into typed nodes (dry-run report first, apply after review).
- **Revert** — full uninstall restores your workspace from a backup
  manifest. Byte-identical, verified.

## Install

```bash
./install.sh [workspace_dir]
```

Preflight checks dependencies and degrades loudly: no flashrank → lexical
rerank; no ONNX/ollama → FTS-only mode. Then stages into
`<workspace>/engram/`, initializes a fresh DB, and generates a migration
dry-run report for your review:

```bash
python3 engram/engram-migrate.py --apply   # after reviewing the report
python3 engram/engram-rewire.py            # backup + rewire md files
python3 engram/engram-seed-battery.py      # verify with mined recall cases
```

## Uninstall

```bash
python3 engram/engram-uninstall.py          # restore + archive db
python3 engram/engram-uninstall.py --purge  # also delete the archived db
```

Restores every touched file from the manifest, removes managed cron lines,
stops the daemon. Idempotent.

## Configuration

Everything lives in `engram/engram.json` — workspace root, DB path, socket,
embedding model, ollama URL, semantic mode. Zero hardcoded paths. Env
overrides via `ENGRAM_CONFIG`.

## Runtime cost

No cloud LLM calls anywhere in the runtime. Recurring pipelines are
deterministic script + SQL + embedding math. An optional small local model
(via ollama) phrases nightly digests; everything falls back to extractive
mode when it's absent.

## License

MIT — see [LICENSE](LICENSE).
