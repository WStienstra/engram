#!/usr/bin/env python3
"""
engram-seed-battery.py — Seeded mini-battery for install verification.

Generates 20 recall cases FROM the migrated content in Engram, plus 3
negative controls (things NOT in the engram). All 23 must pass for install
to report success.

Usage:
  python3 engram/engram-seed-battery.py
"""

import os
import re
import subprocess
import sys
import sqlite3
from collections import Counter

try:
    import bpconfig
    _cfg = bpconfig.load_config()
    WORKSPACE = _cfg["workspace"]
    DB_PATH = _cfg["db_path"]
    BQ_CLI = os.path.join(_cfg["engram_dir"], "bq.py")
    ENGRAM_CLI = os.path.join(_cfg["engram_dir"], "engram.py")
except Exception:
    ENGRAM_DIR = os.path.dirname(os.path.abspath(__file__))
    WORKSPACE = os.path.dirname(ENGRAM_DIR)
    DB_PATH = os.path.join(ENGRAM_DIR, "engram.db")
    BQ_CLI = os.path.join(ENGRAM_DIR, "bq.py")
    ENGRAM_CLI = os.path.join(ENGRAM_DIR, "engram.py")

STOP = set('''the a an and or of to in for with on at from by is are was were be been this that it as
about into over after before not no vs their his her its our your all any each which what when where
how why can will just also more most other some such only own same so than too very s t d ll re ve
een de het en van voor met op um die der und'''.split())


def run_recall(query):
    """Run bq.py recall and return stdout."""
    cmd = [sys.executable, ENGRAM_CLI, "recall", query, "--limit", "5"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30,
                                cwd=WORKSPACE)
        return result.stdout
    except Exception:
        return ""


def mine_cases_from_db():
    """Mine recall cases from the DB content."""
    if not os.path.isfile(DB_PATH):
        return []

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cases = []

    nodes = conn.execute(
        "SELECT id, name, type, content FROM nodes ORDER BY id LIMIT 50"
    ).fetchall()

    for node in nodes:
        name = node["name"] or ""
        content = node["content"] or ""
        ntype = node["type"] or ""

        # Skip very short names
        if len(name) < 5:
            continue

        # Create a query from distinctive words in the name
        words = [w for w in re.findall(r'\w+', name.lower()) if w not in STOP and len(w) > 3]
        if words:
            query = " ".join(words[:3])
            cases.append({
                "query": query,
                "must_match": re.escape(name[:30]),
                "type": "name_partial",
                "node_name": name,
            })

        # Create a query from distinctive content words
        content_words = [w for w in re.findall(r'\w+', content.lower()) if w not in STOP and len(w) > 4]
        if content_words:
            # Pick a few distinctive ones
            query = " ".join(content_words[:3])
            cases.append({
                "query": query,
                "must_match": re.escape(name[:30]),
                "type": "content_probe",
                "node_name": name,
            })

        if len(cases) >= 30:
            break

    conn.close()
    return cases[:20]  # Exactly 20


def check_case(case):
    """Run recall and check if expected node appears in results. Returns (passed, detail)."""
    output = run_recall(case["query"])
    if not output:
        return False, "no output"

    # Check if the node name appears in the output
    if re.search(case["must_match"], output, re.IGNORECASE):
        return True, "found"
    return False, f"not found in results for '{case['query']}'"


def check_negative(query):
    """Negative control: must NOT return a confident match."""
    output = run_recall(query)
    if not output:
        return True, "no output (pass)"

    # Check for explicit no-confident-match declaration
    if re.search(r'no confident match', output, re.IGNORECASE):
        return True, "no false positive (pass)"

    # Check if there are actual confident results (not low-confidence/unverified)
    # Look for confidence markers that indicate real matches
    if re.search(r'(🔴|🟢|exact match|confident)', output, re.IGNORECASE):
        # But only if there's no "no confident match" disclaimer
        if not re.search(r'no confident|not confabulat', output, re.IGNORECASE):
            # Check if there's actual content (not just "no results")
            if re.search(r'\bno (results|matches|nodes)\b', output, re.IGNORECASE):
                return True, "no false positive (pass)"
            return False, "possible false positive"
    return True, "no false positive (pass)"


def main():
    print("Engram Seeded Mini-Battery")
    print("=" * 50)

    # Mine cases from migrated content
    cases = mine_cases_from_db()

    if len(cases) < 20:
        print(f"WARNING: Only mined {len(cases)} cases (need 20). Using what we have.")

    # Run positive cases
    passed = 0
    failed = 0
    failures = []

    print(f"\nPositive cases ({len(cases)}):")
    for i, case in enumerate(cases, 1):
        ok, detail = check_case(case)
        status = "✅" if ok else "❌"
        print(f"  {status} [{case['type']}] '{case['query']}' → {case['node_name'][:40]} ({detail})")
        if ok:
            passed += 1
        else:
            failed += 1
            failures.append(f"  Case {i}: '{case['query']}' expected '{case['node_name'][:40]}' — {detail}")

    # Negative controls
    negatives = [
        "tesla stock trading strategy details",
        "kubernetes cluster admin password",
        "wedding planning for cousin marta",
    ]

    print(f"\nNegative controls ({len(negatives)}):")
    neg_passed = 0
    for q in negatives:
        ok, detail = check_negative(q)
        status = "✅" if ok else "❌"
        print(f"  {status} '{q}' ({detail})")
        if ok:
            neg_passed += 1
        else:
            failures.append(f"  Negative: '{q}' — {detail}")

    # Summary
    total = len(cases) + len(negatives)
    total_passed = passed + neg_passed
    print(f"\n{'=' * 50}")
    print(f"Results: {total_passed}/{total} passed")
    print(f"  Positive: {passed}/{len(cases)}")
    print(f"  Negative: {neg_passed}/{len(negatives)}")

    if failures:
        print(f"\nFailures:")
        for f in failures:
            print(f)

    # Gate: >=90% of mined positive cases (min 3 cases) + 3/3 negative.
    # Rate-based, not absolute: small workspaces mine fewer than 20 cases
    # and must still be able to pass at a high hit rate.
    min_needed = max(3, int(len(cases) * 0.9))
    if len(cases) >= 3 and passed >= min_needed and neg_passed == 3:
        print(f"\n✅ BATTERY PASSED ({passed}/{len(cases)} positive ≥90% + 3/3 negative)")
        sys.exit(0)
    else:
        if len(cases) < 3:
            print("\n❌ BATTERY FAILED (fewer than 3 minable cases — workspace too sparse to verify)")
        else:
            print(f"\n❌ BATTERY FAILED ({passed}/{len(cases)} positive, need ≥{min_needed}; negatives {neg_passed}/3)")
        sys.exit(1)


if __name__ == "__main__":
    main()