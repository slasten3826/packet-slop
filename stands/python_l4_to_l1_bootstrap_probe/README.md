# python_l4_to_l1_bootstrap_probe

First rough `L4 -> L1` probe.

Purpose:

- take a long bootstrap/master prompt
- run it through a local frozen transformer tokenizer
- take the earliest visible material as-is
- export that material as a Lua table for `L1`

This stand does **not** ask the model for an answer.

It only extracts the first textual dirt that will become the basis of `L1 ring`.

## Current scope

Current version exports:

- raw token ids
- token count
- token strings
- prompt text

This is the first honest and minimal bridge:

```text
bootstrap prompt -> tokenization -> L1 ring
```

Later versions may add:

- embeddings
- positionalized embeddings
- early attention

## Fat bootstrap via ProcessLang texts

You may generate a much larger bootstrap prompt from the ProcessLang operator corpus.

Example:

```bash
python3 /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/build_pl_bootstrap.py \
  --operators flow connect dissolve encode choose observe \
  --out /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/master_prompt_pl_ru.txt
```

Then run extraction against that generated prompt file.

## Default intended model

Current first target:

- Russian-oriented local `paradox`

Example model path:

- `/home/slasten/Meta-Llama-3.1-8B-Instruct/merged_paradox`

## Usage

Use the model-local venv:

```bash
'/home/slasten/Meta-Llama-3.1-8B-Instruct/venv/bin/python' \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/extract_bootstrap.py \
  --model /home/slasten/Meta-Llama-3.1-8B-Instruct/merged_paradox \
  --prompt-file /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/master_prompt_ru.txt \
  --out /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/bootstrap_dump.lua
```

Then feed the result into:

- `/home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_bootstrap_from_l4_stand/main.lua`
