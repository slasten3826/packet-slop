# python_l3_dynamic_lora_stand

First executable stand for the `L3 -> L4` dynamic LoRA hypothesis.

This stand does **not** soft-prompt the model.
It does **not** change frozen base weights.

It does this instead:

- takes a compact `L3` summary vector
- projects it into low-rank adapter tensors
- applies those tensors to frozen residual hidden states

That is the first honest shape of a "living LoRA adapter":

`L3 state -> dynamic low-rank tensors -> frozen L4 hidden stream`

## Usage

```bash
'/home/slasten/Meta-Llama-3.1-8B-Instruct/venv/bin/python' \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l3_dynamic_lora_stand/demo.py \
  --model /home/slasten/Meta-Llama-3.1-8B-Instruct/merged_paradox
```

First compare generation with and without dynamic LoRA:

```bash
'/home/slasten/Meta-Llama-3.1-8B-Instruct/venv/bin/python' \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l3_dynamic_lora_stand/generate_compare.py \
  --model /home/slasten/Meta-Llama-3.1-8B-Instruct/merged_paradox \
  --bootstrap-dump /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua \
  --prompt 'Что сейчас происходит в машине?' \
  --strength 1e-5
```

## What it proves

- we can generate low-rank adapter tensors from live `L3` state
- we can apply them without touching frozen base weights
- we can target concrete layers of the external transformer

It is still a probe, not the final bridge.
But this is already the correct direction for `L3 as living LoRA adapter`.
