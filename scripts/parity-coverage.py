#!/usr/bin/env python3
"""解析 Tortoise inventory Markdown，输出 ✅/总数 覆盖率报表。

用法：
  python3 scripts/parity-coverage.py
  python3 scripts/parity-coverage.py --inventory path.md --json out.json
  python3 scripts/parity-coverage.py --fail-below 1.0   # PERFECT 门禁用
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


STATUS_DONE = "done"
STATUS_PARTIAL = "partial"
STATUS_MISSING = "missing"


@dataclass
class CoverageItem:
    key: str
    section: str
    title: str
    raw_status: str
    status: str


def classify_status(cell: str) -> str:
    text = cell.strip()
    if not text:
        return STATUS_MISSING
    # 纯完成
    if text == "✅" or (text.startswith("✅") and "❌" not in text and "🟡" not in text):
        return STATUS_DONE
    # 明确缺失优先于混合表述中的「有一点」
    if "❌" in text or "缺口" in text:
        # ❌/🟡 仍算未完成（partial），便于区分「全无」与「半成品」
        if "🟡" in text or "弱" in text or "部分" in text:
            return STATUS_PARTIAL
        return STATUS_MISSING
    if "🟡" in text or "弱" in text or "部分" in text:
        return STATUS_PARTIAL
    # 无 emoji 的「弱」已覆盖；其余未知当 missing
    return STATUS_MISSING


def split_row(line: str) -> list[str]:
    raw = line.strip()
    if not raw.startswith("|"):
        return []
    parts = [p.strip() for p in raw.strip("|").split("|")]
    return parts


def parse_inventory(markdown: str) -> list[CoverageItem]:
    items: list[CoverageItem] = []
    section = "unknown"

    for line in markdown.splitlines():
        if line.startswith("## "):
            heading = line[3:].strip()
            if heading.startswith("2."):
                section = "domain"
            elif heading.startswith("3."):
                section = "command"
            elif heading.startswith("5."):
                section = "log"
            elif heading.startswith("6."):
                section = "settings"
            elif heading.startswith("7."):
                section = "overlay"
            else:
                section = "other"
            continue

        if not line.startswith("|"):
            continue
        cells = split_row(line)
        if len(cells) < 2:
            continue
        # 跳过表头与分隔行
        if cells[0] in {"域 ID", "L#", "S#", "状态", "#"} or set(cells[0]) <= {"-", ":"}:
            continue
        if all(set(c) <= {"-", ":"} for c in cells):
            continue

        if section == "domain" and re.fullmatch(r"D\d{2}", cells[0]):
            # | D01 | name | points | Studio | wave |
            if len(cells) < 4:
                continue
            items.append(
                CoverageItem(
                    key=cells[0],
                    section=section,
                    title=cells[1],
                    raw_status=cells[3],
                    status=classify_status(cells[3]),
                )
            )
        elif section == "command" and re.fullmatch(r"\d+", cells[0]):
            # | # | name | cli | options | Studio | wave |
            if len(cells) < 5:
                continue
            num = int(cells[0])
            items.append(
                CoverageItem(
                    key=f"cmd.{num:02d}",
                    section=section,
                    title=cells[1],
                    raw_status=cells[4],
                    status=classify_status(cells[4]),
                )
            )
        elif section == "log" and re.fullmatch(r"L\d{2}", cells[0]):
            if len(cells) < 4:
                continue
            items.append(
                CoverageItem(
                    key=cells[0],
                    section=section,
                    title=cells[1],
                    raw_status=cells[3],
                    status=classify_status(cells[3]),
                )
            )
        elif section == "settings" and re.fullmatch(r"S\d{2}", cells[0]):
            if len(cells) < 4:
                continue
            items.append(
                CoverageItem(
                    key=cells[0],
                    section=section,
                    title=cells[1],
                    raw_status=cells[3],
                    status=classify_status(cells[3]),
                )
            )
        elif section == "overlay" and len(cells) >= 3 and cells[0] not in {"状态"}:
            # | 状态 | Studio | 波次 |
            items.append(
                CoverageItem(
                    key=f"overlay.{len([i for i in items if i.section == 'overlay']) + 1:02d}",
                    section=section,
                    title=cells[0],
                    raw_status=cells[1],
                    status=classify_status(cells[1]),
                )
            )

    return items


def build_report(items: list[CoverageItem]) -> dict:
    total = len(items)
    done = sum(1 for i in items if i.status == STATUS_DONE)
    partial = sum(1 for i in items if i.status == STATUS_PARTIAL)
    missing = sum(1 for i in items if i.status == STATUS_MISSING)
    ratio = (done / total) if total else 0.0

    by_section: dict[str, dict[str, int]] = {}
    for item in items:
        bucket = by_section.setdefault(
            item.section, {"total": 0, "done": 0, "partial": 0, "missing": 0}
        )
        bucket["total"] += 1
        bucket[item.status] += 1

    return {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "total": total,
        "done": done,
        "partial": partial,
        "missing": missing,
        "coverage": round(ratio, 6),
        "coverage_percent": round(ratio * 100, 2),
        "formula": "done / total （仅 ✅ 计入 done；🟡/弱/部分=partial；❌/缺口=missing）",
        "by_section": by_section,
        "items": [asdict(i) for i in items],
    }


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Tortoise parity coverage reporter")
    parser.add_argument(
        "--inventory",
        type=Path,
        default=repo_root
        / "docs/superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md",
    )
    parser.add_argument(
        "--json",
        type=Path,
        default=repo_root / "docs/acceptance/parity-coverage.json",
    )
    parser.add_argument(
        "--fail-below",
        type=float,
        default=None,
        help="若 coverage 低于该阈值（0~1）则以退出码 1 失败",
    )
    args = parser.parse_args()

    if not args.inventory.is_file():
        print(f"parity-coverage: inventory 不存在: {args.inventory}", file=sys.stderr)
        return 2

    markdown = args.inventory.read_text(encoding="utf-8")
    items = parse_inventory(markdown)
    report = build_report(items)

    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(
        f"parity-coverage: {report['done']}/{report['total']} "
        f"= {report['coverage_percent']}%  "
        f"(partial={report['partial']}, missing={report['missing']})"
    )
    for name, bucket in sorted(report["by_section"].items()):
        print(
            f"  - {name}: {bucket['done']}/{bucket['total']} "
            f"(partial={bucket['partial']}, missing={bucket['missing']})"
        )
    print(f"parity-coverage: wrote {args.json}")

    if args.fail_below is not None and report["coverage"] < args.fail_below:
        print(
            f"parity-coverage: FAIL coverage {report['coverage']} < {args.fail_below}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
