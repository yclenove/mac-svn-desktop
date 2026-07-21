#!/usr/bin/env python3
"""parity-coverage.py 的最小契约测试（fixture，不依赖真实 inventory 全量）。"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "parity-coverage.py"

FIXTURE = """# Fixture

## 2. DUG 能力域

| 域 ID | DUG 章节 | 必须覆盖的能力要点 | Studio | 波次 |
|-------|----------|-------------------|--------|------|
| D01 | Icon | x | 🟡 | T4 |
| D02 | Menu | y | ✅ | T1 |

## 3. 命令矩阵

| # | 命令 | 核心 | 对话框 | Studio | 波次 |
|---|------|------|--------|--------|------|
| 1 | Checkout | co | depth | 🟡 | T2 |
| 2 | Update | up | 进度 | ❌ | T1 |

## 5. Show Log

| L# | 动作 | 说明 | Studio | 波次 |
|----|------|------|--------|------|
| L01 | Compare | x | ❌ | T2 |
| L07 | Blame | y | 🟡 | T2 |

## 6. 设置页

| S# | 页 | 项 | Studio | 波次 |
|----|----|----|--------|------|
| S01 | General | a | 弱 | T5 |
| S02 | Menu | b | ❌ | T4 |

## 7. Overlay

| 状态 | Studio | 波次 |
|------|--------|------|
| Normal | 部分 | T4 |
| Locked | 缺口 | T4 |
"""


class ParityCoverageTests(unittest.TestCase):
    def test_fixture_counts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            inv = Path(tmp) / "inv.md"
            out = Path(tmp) / "out.json"
            inv.write_text(FIXTURE, encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, str(SCRIPT), "--inventory", str(inv), "--json", str(out)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("1/10", proc.stdout)
            report = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(report["total"], 10)
            self.assertEqual(report["done"], 1)
            self.assertEqual(report["partial"], 5)  # D01, cmd1, L07, S01, overlay Normal
            self.assertEqual(report["missing"], 4)  # cmd2, L01, S02, overlay Locked
            self.assertAlmostEqual(report["coverage"], 0.1)
            keys = {item["key"] for item in report["items"]}
            self.assertIn("cmd.01", keys)
            self.assertIn("L01", keys)
            self.assertIn("S01", keys)
            self.assertIn("overlay.01", keys)

    def test_fail_below(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            inv = Path(tmp) / "inv.md"
            out = Path(tmp) / "out.json"
            inv.write_text(FIXTURE, encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--inventory",
                    str(inv),
                    "--json",
                    str(out),
                    "--fail-below",
                    "1.0",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 1)


if __name__ == "__main__":
    unittest.main()
