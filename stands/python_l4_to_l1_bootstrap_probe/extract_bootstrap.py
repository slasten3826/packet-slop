#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path
from transformers import AutoTokenizer


def lua_quote(text: str) -> str:
    escaped = (
        text.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return "'" + escaped + "'"


def build_dump(prompt_text: str, model_path: str, token_ids: list[int], token_texts: list[str]) -> str:
    lines: list[str] = []
    lines.append("return {")
    lines.append(f"  model_path = {lua_quote(model_path)},")
    lines.append(f"  prompt = {lua_quote(prompt_text)},")
    lines.append(f"  token_count = {len(token_ids)},")

    lines.append("  token_ids = {")
    for idx, token_id in enumerate(token_ids, start=1):
        suffix = "," if idx < len(token_ids) else ""
        lines.append(f"    {token_id}{suffix}")
    lines.append("  },")

    lines.append("  token_texts = {")
    for idx, token_text in enumerate(token_texts, start=1):
        suffix = "," if idx < len(token_texts) else ""
        lines.append(f"    {lua_quote(token_text)}{suffix}")
    lines.append("  },")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="Path to local HF-compatible model directory")
    parser.add_argument("--prompt-file", required=True, help="Path to bootstrap prompt text file")
    parser.add_argument("--out", required=True, help="Path to Lua dump file")
    args = parser.parse_args()

    model_path = Path(args.model)
    prompt_file = Path(args.prompt_file)
    out_file = Path(args.out)

    prompt_text = prompt_file.read_text(encoding="utf-8").strip()

    tokenizer = AutoTokenizer.from_pretrained(str(model_path), use_fast=True)
    encoded = tokenizer(prompt_text, add_special_tokens=True, return_attention_mask=False)
    token_ids: list[int] = list(encoded["input_ids"])
    token_texts = [
        tokenizer.decode([token_id], clean_up_tokenization_spaces=False)
        for token_id in token_ids
    ]

    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_text(
        build_dump(prompt_text=prompt_text, model_path=str(model_path), token_ids=token_ids, token_texts=token_texts),
        encoding="utf-8",
    )

    print("l4 bootstrap probe")
    print(f"model={model_path}")
    print(f"prompt_file={prompt_file}")
    print(f"out={out_file}")
    print(f"token_count={len(token_ids)}")
    print("token_preview=" + ",".join(token_texts[:24]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
