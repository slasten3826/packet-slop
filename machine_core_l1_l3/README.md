# machine_core_l1_l3

This directory is the current clean entrypoint for the working `L1-L3` machine.

It exists because `stands/` is now a research junkyard.

If you want the current machine body instead of the whole archive,
start here.

## Scope

This curated core currently includes:

- `L4 -> L1` bootstrap through local frozen transformer
- canonical `L1(C)` chaos body
- `Mx(L1)` experiments
- `Mx(L1+L2)` experiments
- current `L2 -> L3` Eva.00 body
- first `L3 -> dynamic LoRA -> frozen L4` bridge

This directory does **not** replace the old stands.
It points at the small subset that currently matters.

## Canonical Flow

Current working route:

1. `ProcessLang DSL`
2. `compiler(v2)`
3. transformer token bootstrap
4. `L1(C)` chaos ring
5. `L2` formation body
6. current `L3` body

## Canonical Files

### Bootstrap source

- [processlang_bootstrap_machine_ru.txt](/home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru.txt)
- [processlang_bootstrap_machine_ru_v2.txt](/home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.txt)
- [processlang_bootstrap_machine_ru_v2.lua](/home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua)

### `L1`

- [lua_l1_bootstrap_from_l4_stand/main.lua](/home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_bootstrap_from_l4_stand/main.lua)

### `Mx(L1)`

- [lua_l1_multiplier_stand/main.lua](/home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_multiplier_stand/main.lua)

### `Mx(L1+L2)`

- [lua_l1_l2_multiplier_stand/main.lua](/home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_l2_multiplier_stand/main.lua)

### Current `L2 -> L3`

- [lua_eva00_l2_l3_stand/main.lua](/home/slasten/dev/packetLearning/packet-slop/stands/lua_eva00_l2_l3_stand/main.lua)

### Current `L3 -> L4`

- [dynamic_lora.py](/home/slasten/dev/packetLearning/packet-slop/stands/python_l3_dynamic_lora_stand/dynamic_lora.py)
- [generate_compare.py](/home/slasten/dev/packetLearning/packet-slop/stands/python_l3_dynamic_lora_stand/generate_compare.py)

## Current Open Question

The hard unresolved point is now `L3`.

Not philosophically.
Technically.

The bridge into frozen `L4` already exists.
What does not yet exist is a non-degenerate `L3` body that can produce a
real adapter-state instead of collapsing into trivial summaries.

## Read Next

1. [RUNBOOK_RU.md](/home/slasten/dev/packetLearning/packet-slop/machine_core_l1_l3/RUNBOOK_RU.md)
2. [STATE_RU.md](/home/slasten/dev/packetLearning/packet-slop/machine_core_l1_l3/STATE_RU.md)
3. [55_L3_OPEN_QUESTION_AND_DYNAMIC_LORA_STATUS_RU.md](/home/slasten/dev/packetLearning/packet-slop/docs/55_L3_OPEN_QUESTION_AND_DYNAMIC_LORA_STATUS_RU.md)
