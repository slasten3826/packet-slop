#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path("/home/slasten/dev/packetLearning/stack/ProcessLang/python")

OPERATOR_FILES = {
    "flow": "FluidCore.txt",
    "connect": "EmergentConnection.txt",
    "dissolve": "FormDissolution.txt",
    "encode": "EncodingSystem.txt",
    "choose": "ChoiceMechanism.txt",
    "observe": "SelfObservation.txt",
    "cycle": "EternalCycle.txt",
    "logic": "LogicSimulator.txt",
    "runtime": "SubconsciousRuntime.txt",
    "manifest": "ManifestationEngine.txt",
}


def build_text(operators: list[str]) -> str:
    header = """Ты не отвечаешь пользователю.
Ты не пишешь финальный текст.
Ты не делаешь вывод.

Твоя задача не в ответе, а в разворачивании внутреннего поля машины.
Нужно собрать богатый внутренний субстрат для хаоса, формирования формы, жизни форм и будущей манифестации.

Ниже даны operator texts ProcessLang.
Считай их частью внутреннего bootstrap мира машины.
Не резюмируй их.
Не объясняй их.
Держи их как рабочую внутреннюю среду.
"""

    parts = [header]
    for op in operators:
        filename = OPERATOR_FILES[op]
        path = ROOT / filename
        text = path.read_text(encoding="utf-8").strip()
        parts.append(f"\n=== OPERATOR {op.upper()} :: {filename} ===\n")
        parts.append(text)
        parts.append("\n")
    footer = """
Никакого финального ответа не требуется.
Нужно только внутреннее тематическое возбуждение и насыщение среды.
"""
    parts.append(footer)
    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--operators",
        nargs="+",
        default=["flow", "connect", "dissolve", "encode", "choose", "observe"],
        choices=sorted(OPERATOR_FILES.keys()),
        help="PL operators whose full texts should be injected into the bootstrap prompt",
    )
    parser.add_argument("--out", required=True, help="Output text file")
    args = parser.parse_args()

    out = Path(args.out)
    text = build_text(args.operators)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")

    print("pl bootstrap builder")
    print("operators=" + ",".join(args.operators))
    print(f"out={out}")
    print(f"chars={len(text)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
