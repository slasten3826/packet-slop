# lua_l1_l2_multiplier_stand

First rough `Mx(L1+L2)` stand.

Purpose:

- take one transformer-derived bootstrap dump
- instantiate `M` parallel `L1` cores
- run canonical `L1(C)` on each core
- use each final `L1` fingerprint as the seed of its own `L2 neural boundary`
- compare five resulting `L2` bodies

## Current bridge

This stand does not invent a new `L1 -> L2` law yet.

Current rough bridge:

- `l1_ring = bootstrap token_count`
- `l1_cw = 1` for each core
- final `L1 fp` becomes `L2 seed`

This is intentionally narrow.
The goal is to see whether `Mx5` lower worlds already produce different `L2` bodies.

## Usage

```bash
lua /home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_l2_multiplier_stand/main.lua \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua \
  5
```

Arguments:

1. bootstrap dump `.lua`
2. multiplier `M`
3. optional `L1` ticks, default = `2 * ring`
4. optional `L2` ticks, default = `160`
