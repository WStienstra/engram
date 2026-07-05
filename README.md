# Engram

**Local-first associative memory for OpenClaw agents.** One command in, one
command out. All on SQLite — no cloud, no API keys, no vector database.

## Why Engram

- 🧠 **Remembers like a brain, not like grep** — hybrid recall fuses keyword,
  semantic, tag, and graph channels, then a CPU cross-encoder reranks. Asks
  "what do you know about the hosting setup" and gets the answer, not 50 log lines.
- 🤐 **Honest "I don't know"** — calibrated abstention. When nothing is truly
  grounded it says so instead of confabulating a plausible-sounding wrong answer.
  For an agent memory, this is the feature everything else depends on.
- ⏰ **Sets its own future reminders** — `engram intend "when X" "do Y"` arms a
  prospective intention; the moment the trigger shows up in conversation context,
  the reminder fires. Deterministic keyword matching, ~50ms, no LLM in the loop.
- 📋 **Learns how, not just what** — procedural methods store the way a task was
  done right (steps, pitfalls, verification); the next matching task gets the
  playbook injected automatically.
- 🕰️ **Knows what was true *when*** — bi-temporal facts: `asof "office address"
  --date 2024-06-01` answers from that moment in time. Superseded facts get
  demoted, never silently deleted.
- 🔄 **Leaves no trace on the way out** — install backs up everything it touches
  to a manifest; uninstall restores your workspace byte-identical. Verified by
  a seeded recall battery generated from your own migrated content.
- 🪫 **Runs on nothing** — pure Python + SQLite. Embeddings and reranking are
  optional and degrade loudly to keyword-only mode. No cloud LLM calls anywhere
  in the runtime.

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
