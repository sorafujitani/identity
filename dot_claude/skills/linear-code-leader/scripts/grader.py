#!/usr/bin/env python3
"""Grade linear-code-leader runs by checking objective assertions on outputs/.

Usage:
    python grader.py <iteration_dir>

For each eval-*/<config>/outputs/ directory found, writes a grading.json
sibling to outputs/ with per-assertion {text, passed, evidence}.
"""

import json
import re
import sys
from pathlib import Path


def read_all_outputs(outputs_dir: Path) -> tuple[list[Path], str]:
    """Return (file paths, concatenated text) under outputs_dir."""
    files = sorted([p for p in outputs_dir.rglob("*") if p.is_file()])
    text_parts = []
    for p in files:
        try:
            text_parts.append(p.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            text_parts.append("")
    return files, "\n\n".join(text_parts)


def has_mermaid_block(text: str, kind: str) -> bool:
    """Check if text contains a ```mermaid block of the given kind.

    kind: 'graph'/'flowchart' for architecture, 'sequenceDiagram' for sequence.
    """
    pattern = re.compile(r"```mermaid\b(.*?)```", re.DOTALL)
    for m in pattern.finditer(text):
        body = m.group(1)
        if kind in ("graph", "flowchart"):
            if re.search(r"^\s*(graph|flowchart)\b", body, re.MULTILINE):
                return True
        elif kind == "sequenceDiagram":
            if re.search(r"^\s*sequenceDiagram\b", body, re.MULTILINE):
                return True
    return False


def count_file_line_refs(text: str) -> int:
    """Count occurrences of file:line references like src/foo.ts:42 or _client.py:120."""
    pattern = re.compile(r"[\w./\-]+\.(?:ts|tsx|js|jsx|go|py|rs|java|kt|rb|php|cs):\d+")
    return len(pattern.findall(text))


def has_scope_statement(files: list[Path], text: str) -> tuple[bool, str]:
    """Look for a scope declaration. Either a file with 'scope' in the name,
    or the words 'スコープ' / 'Scope' / 'scope' in an early header context."""
    for p in files:
        name = p.name.lower()
        if "scope" in name or name.startswith("00_"):
            content = p.read_text(encoding="utf-8", errors="replace")
            if any(k in content for k in ["スコープ", "Scope", "scope", "目的", "Goal"]):
                return True, f"found in {p.name}"
    if any(k in text for k in ["## スコープ", "# スコープ", "## Scope", "# Scope"]):
        return True, "scope heading present"
    return False, ""


def has_glossary(text: str) -> bool:
    return bool(re.search(r"用語集|glossary|terminology|Glossary|Terminology", text))


def has_understanding_doc(files: list[Path]) -> bool:
    return any("understanding" in p.name.lower() for p in files)


def references_repo_files(text: str, expected_paths: list[str]) -> int:
    """Count how many of expected_paths appear in text (substring match)."""
    return sum(1 for path in expected_paths if path in text)


# Per-eval expected real-repo paths (sampled known files from the cloned repos)
EVAL_EXPECTED = {
    "eval-1-typescript-framework": {
        "expected_paths": [
            "src/hono.ts",
            "src/router",
            "src/context",
            "src/types",
            "hono-base",
        ],
        "flow_keywords": ["リクエスト", "ハンドラ", "request", "handler", "Hono"],
        "domain": "hono",
    },
    "eval-2-go-cli": {
        "expected_paths": [
            "main.go",
            "ui/",
            "cmd",
            "bubbletea",
            "tea.Program",
            "glamour",
        ],
        "flow_keywords": ["glow", "Markdown", "render", "TUI", "bubbletea"],
        "domain": "glow",
    },
    "eval-3-python-library": {
        "expected_paths": [
            "_client.py",
            "_transports",
            "_models",
            "_api.py",
            "Client",
            "Transport",
        ],
        "flow_keywords": ["httpx.get", "Request", "Response", "Transport", "send"],
        "domain": "httpx",
    },
}


def grade_one(eval_name: str, outputs_dir: Path) -> list[dict]:
    files, text = read_all_outputs(outputs_dir)
    cfg = EVAL_EXPECTED.get(eval_name, {})
    expected_paths = cfg.get("expected_paths", [])
    flow_keywords = cfg.get("flow_keywords", [])

    assertions = []

    # 1. produced at least 3 files
    assertions.append({
        "text": "成果物ファイルが3つ以上保存されている",
        "passed": len(files) >= 3,
        "evidence": f"{len(files)} files: {[p.name for p in files[:8]]}",
    })

    # 2. has architecture mermaid (graph / flowchart)
    has_arch = has_mermaid_block(text, "graph") or has_mermaid_block(text, "flowchart")
    assertions.append({
        "text": "Mermaid のアーキテクチャ図 (graph/flowchart) が含まれる",
        "passed": has_arch,
        "evidence": "mermaid graph/flowchart block found" if has_arch else "no mermaid graph/flowchart",
    })

    # 3. has sequence diagram
    has_seq = has_mermaid_block(text, "sequenceDiagram")
    assertions.append({
        "text": "Mermaid のシーケンス図 (sequenceDiagram) が Phase 4 にある",
        "passed": has_seq,
        "evidence": "mermaid sequenceDiagram block found" if has_seq else "no sequenceDiagram",
    })

    # 4. has file:line references >= 3 (proves flow trace anchored in real code)
    n_refs = count_file_line_refs(text)
    assertions.append({
        "text": "ファイル:行番号 参照が3件以上ある (フロー追跡が実コードに紐付いている)",
        "passed": n_refs >= 3,
        "evidence": f"{n_refs} file:line references",
    })

    # 5. scope declaration
    has_scope, scope_ev = has_scope_statement(files, text)
    assertions.append({
        "text": "冒頭でスコープ宣言が行われている (Phase 0)",
        "passed": has_scope,
        "evidence": scope_ev or "no scope statement",
    })

    # 6. has UNDERSTANDING.md (Phase 6 統合)
    has_und = has_understanding_doc(files)
    assertions.append({
        "text": "統合ドキュメント (UNDERSTANDING.md 相当) が存在する (Phase 6)",
        "passed": has_und,
        "evidence": "UNDERSTANDING.md found" if has_und else "missing",
    })

    # 7. has glossary
    has_glo = has_glossary(text)
    assertions.append({
        "text": "用語集 / glossary セクションが存在する (Phase 3)",
        "passed": has_glo,
        "evidence": "glossary section found" if has_glo else "missing",
    })

    # 8. references real repo files (>= 3 of expected paths)
    if expected_paths:
        n_real = references_repo_files(text, expected_paths)
        assertions.append({
            "text": f"実リポジトリのファイル/シンボルへの言及が3つ以上 ({cfg.get('domain','')})",
            "passed": n_real >= 3,
            "evidence": f"{n_real}/{len(expected_paths)} expected paths referenced",
        })

    # 9. flow keywords (specific to the eval's representative flow)
    if flow_keywords:
        hits = sum(1 for kw in flow_keywords if kw in text)
        assertions.append({
            "text": f"代表フローのキーワード ({', '.join(flow_keywords[:3])}…) が3つ以上含まれる",
            "passed": hits >= 3,
            "evidence": f"{hits}/{len(flow_keywords)} flow keywords matched",
        })

    return assertions


def main():
    if len(sys.argv) != 2:
        print("Usage: grader.py <iteration_dir>", file=sys.stderr)
        sys.exit(1)

    iteration_dir = Path(sys.argv[1]).resolve()
    if not iteration_dir.is_dir():
        print(f"Not a directory: {iteration_dir}", file=sys.stderr)
        sys.exit(1)

    eval_dirs = sorted([p for p in iteration_dir.iterdir() if p.is_dir() and p.name.startswith("eval-")])
    summary = []
    for eval_dir in eval_dirs:
        for run_dir in sorted([p for p in eval_dir.iterdir() if p.is_dir()]):
            outputs_dir = run_dir / "outputs"
            if not outputs_dir.exists():
                continue
            assertions = grade_one(eval_dir.name, outputs_dir)
            passed = sum(1 for a in assertions if a["passed"])
            total = len(assertions)
            grading = {
                "eval_name": eval_dir.name,
                "configuration": run_dir.name,
                "expectations": assertions,
                "summary": {
                    "passed": passed,
                    "failed": total - passed,
                    "total": total,
                    "pass_rate": round(passed / total, 4) if total else 0.0,
                },
            }
            out_path = run_dir / "grading.json"
            out_path.write_text(json.dumps(grading, ensure_ascii=False, indent=2))
            summary.append((eval_dir.name, run_dir.name, grading["summary"]))
            print(f"  graded {eval_dir.name}/{run_dir.name}: {grading['summary']['passed']}/{grading['summary']['total']}")

    print("\nDone.")


if __name__ == "__main__":
    main()
