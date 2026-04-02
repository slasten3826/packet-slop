# lua_l1_bootstrap_from_l4_stand

First rough `L4 -> L1` stand.

Purpose:

- load raw early material exported from a local transformer tokenizer
- make this material the initial `L1 ring`
- run the existing `crazy` law over that ring

This stand does **not** invent new `L1` control knobs.

It uses:

- ring size = token count from bootstrap dump
- existing `ticks`
- existing `variant`

## Current law

Current initialization:

- `ring = token_count`
- `core[i] = token_ids[i] % 59049`
- `trace[i] = crazy(core[i], phase[i])`
- `carry = token_ids[1] % 59049`

This is intentionally rough.

The goal is not elegance.
The goal is to see whether transformer bootstrap dirt can become a living `L1` ring at all.

## Usage

First generate bootstrap dump:

```bash
'/home/slasten/Meta-Llama-3.1-8B-Instruct/venv/bin/python' \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/extract_bootstrap.py \
  --model /home/slasten/Meta-Llama-3.1-8B-Instruct/merged_paradox \
  --prompt-file /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/master_prompt_ru.txt \
  --out /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/bootstrap_dump.lua
```

Then run:

```bash
lua /home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_bootstrap_from_l4_stand/main.lua \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/bootstrap_dump.lua \
  512 \
  A
```
