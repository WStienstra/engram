#!/usr/bin/env bash
#
# Engram install.sh — One-install Engram setup for any OpenClaw workspace.
#
# Flow: PREFLIGHT → STAGE → INIT → MIGRATE (dry-run gated) → REWIRE → VERIFY
#
# Usage:
#   ./install.sh [workspace_dir]    # default: parent of this script's dir
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${1:-$(dirname "$SCRIPT_DIR")}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✅${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
err()   { echo -e "${RED}❌${NC} $*"; }

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Engram — Engram Installer         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""
info "Workspace: $WORKSPACE"
echo ""

# ── 1. PREFLIGHT ────────────────────────────────────────────────────────────
echo -e "${BLUE}━━ 1. PREFLIGHT ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Python version
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 10 ]; then
    ok "Python $PY_VER (≥3.10)"
else
    err "Python $PY_VER found — need ≥3.10"
    exit 1
fi

# Check pip deps
PIP_OK=true
python3 -c "import numpy" 2>/dev/null && ok "numpy: installed" || { warn "numpy: NOT installed (semantic search needs this)"; PIP_OK=false; }
python3 -c "import onnxruntime" 2>/dev/null && ok "onnxruntime: installed" || { warn "onnxruntime: NOT installed (semantic search needs this)"; PIP_OK=false; }

# Flashrank (optional — degrade to lexical rerank)
HAS_FLASHRANK=false
python3 -c "import flashrank" 2>/dev/null && { ok "flashrank: installed (cross-encoder rerank)"; HAS_FLASHRANK=true; } || warn "flashrank: NOT installed — will use lexical rerank (degraded mode)"

# Ollama check (optional — for ollama embed mode)
HAS_OLLAMA=false
if command -v ollama &>/dev/null; then
    if ollama list 2>/dev/null | grep -q "nomic-embed-text"; then
        ok "ollama: running with nomic-embed-text"
        HAS_OLLAMA=true
    else
        warn "ollama: installed but nomic-embed-text not pulled. Semantic search will use ONNX mode."
        info "  To enable ollama embeddings: ollama pull nomic-embed-text (~275MB)"
    fi
else
    warn "ollama: NOT installed — semantic search will use ONNX mode (or FTS-only if no ONNX model)"
fi

# If neither onnxruntime nor ollama: FTS-only mode
if [ "$PIP_OK" = false ] && [ "$HAS_OLLAMA" = false ]; then
    warn "⚠️  NO SEMANTIC SEARCH AVAILABLE — installing in FTS-only mode"
    warn "   recall will work but without semantic similarity ranking"
fi

# Disk check
AVAIL_KB=$(df "$WORKSPACE" 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 1048576 ]; then
    err "Less than 1GB disk space available ($(( AVAIL_KB / 1024 ))MB)"
    exit 1
fi
ok "Disk space: $(( AVAIL_KB / 1024 ))MB available"

echo ""

# ── 2. STAGE ────────────────────────────────────────────────────────────────
echo -e "${BLUE}━━ 2. STAGE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

ENGRAM_DIR="$WORKSPACE/engram"
SCRIPTS_DIR="$WORKSPACE/scripts"

# Guard: abort if engram/ already exists
if [ -d "$ENGRAM_DIR" ]; then
    # Check if it's a real engram (has engram.py or engram.db)
    if [ -f "$ENGRAM_DIR/engram.py" ] || [ -f "$ENGRAM_DIR/engram.db" ]; then
        err "Existing engram/ directory found at $ENGRAM_DIR"
        err "Engram will NOT overwrite an existing engram. Aborting."
        err "To reinstall: run 'python3 $ENGRAM_DIR/engram-uninstall.py' first"
        exit 1
    fi
fi

# Create directories
mkdir -p "$ENGRAM_DIR" "$SCRIPTS_DIR"

# Copy engine files
info "Copying engine files to $ENGRAM_DIR/..."
for f in engram.py bq.py engram-serve.py engram-sleep.py engram-backup.py \
         engram-battery.py engram-migrate.py engram-rewire.py \
         engram-uninstall.py engram-seed-battery.py bpconfig.py embeddings.py; do
    if [ -f "$SCRIPT_DIR/engine/$f" ]; then
        cp "$SCRIPT_DIR/engine/$f" "$ENGRAM_DIR/$f"
    fi
done

# Copy script files to scripts/
for f in engram-backup.py engram-sleep.py engram-battery.py; do
    if [ -f "$SCRIPT_DIR/engine/$f" ]; then
        cp "$SCRIPT_DIR/engine/$f" "$SCRIPTS_DIR/$f"
    fi
done

# Write config
info "Writing engram/engram.json config..."
python3 -c "
import json, os
ws = '$WORKSPACE'
cfg = {
    'workspace': ws,
    'db_path': os.path.join(ws, 'engram', 'engram.db'),
    'engram_dir': os.path.join(ws, 'engram'),
    'scripts_dir': os.path.join(ws, 'scripts'),
    'logs_dir': os.path.join(ws, 'logs'),
    'backups_dir': os.path.join(ws, 'backups', 'engram'),
    'socket_path': '/tmp/engram-serve.sock',
    'pid_path': '/tmp/engram-serve.pid',
    'embed_model': 'multilingual-e5-small',
    'embed_dim': 384,
    'sleep_model': 'local',
    'ollama_url': 'http://localhost:11434',
    'ollama_embed_model': 'nomic-embed-text',
    'semantic_mode': 'onnx',
    'flashrank_model': 'ms-marco-TinyBERT-L-2-v2',
}
with open(os.path.join(ws, 'engram', 'engram.json'), 'w') as f:
    json.dump(cfg, f, indent=2)
print('  Config written:', os.path.join(ws, 'engram', 'engram.json'))
"

# Make scripts executable
chmod +x "$ENGRAM_DIR"/*.py "$SCRIPTS_DIR"/engram-*.py 2>/dev/null || true

ok "Engine staged"
echo ""

# ── 3. INIT ─────────────────────────────────────────────────────────────────
echo -e "${BLUE}━━ 3. INIT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

info "Running engram init (creates fresh engram.db)..."
cd "$WORKSPACE"
python3 "$ENGRAM_DIR/engram.py" calibrate 2>&1 | head -5 || true

# Check DB was created
if [ ! -f "$ENGRAM_DIR/engram.db" ]; then
    err "engram.db was not created — init failed"
    exit 1
fi
ok "Fresh engram.db created"

# Try to start daemon (optional — degrades gracefully)
if python3 -c "import onnxruntime" 2>/dev/null; then
    info "Starting warm daemon (optional)..."
    nohup python3 "$ENGRAM_DIR/engram-serve.py" > "$WORKSPACE/logs/engram-serve.log" 2>&1 &
    DAEMON_PID=$!
    sleep 2
    # Smoke ping
    if python3 "$ENGRAM_DIR/bq.py" tags 2>/dev/null | head -1; then
        ok "Daemon responding to smoke ping"
    else
        warn "Daemon not responding (will use CLI fallback — this is fine)"
    fi
else
    info "ONNX not available — skipping daemon start (CLI-only mode)"
fi

echo ""

# ── 4. MIGRATE (DRY-RUN GATED) ──────────────────────────────────────────────
echo -e "${BLUE}━━ 4. MIGRATE (DRY-RUN) ━━━━━━━━━━━━━━━━━━${NC}"

info "Running migration dry-run..."
python3 "$ENGRAM_DIR/engram-migrate.py" --dry-run 2>&1

REPORT_PATH="$WORKSPACE/migration-report.md"
if [ -f "$REPORT_PATH" ]; then
    ok "Migration report written to: $REPORT_PATH"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  REVIEW the migration report at: $REPORT_PATH${NC}"
    echo -e "${YELLOW}  When satisfied, run:${NC}"
    echo -e "${YELLOW}    python3 $ENGRAM_DIR/engram-migrate.py --apply${NC}"
    echo -e "${YELLOW}  Then run rewire + verify:${NC}"
    echo -e "${YELLOW}    python3 $ENGRAM_DIR/engram-rewire.py${NC}"
    echo -e "${YELLOW}    python3 $ENGRAM_DIR/engram-seed-battery.py${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    warn "No migration report generated (no md files found in workspace?)"
fi

echo ""
ok "Engram install staged. Next: review report, then --apply."
echo ""
echo "To uninstall: python3 $ENGRAM_DIR/engram-uninstall.py"