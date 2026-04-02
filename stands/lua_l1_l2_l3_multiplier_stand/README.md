# lua_l1_l2_l3_multiplier_stand

First rough `Mx(L1+L2) -> shared fat L3` stand.

Purpose:

- take one transformer-derived bootstrap dump
- instantiate `M` parallel `L1` cores
- run canonical `L1(C)` on each core
- derive `M` separate `L2` bodies from those `L1` states
- let all `L2` bodies spawn crystals into one shared enlarged `L3`

## Current law

This is intentionally rough.

Current bridge:

- `ring = bootstrap token_count`
- `l1_cw = 1` per lower core
- final `L1 fp -> L2 seed`
- shared `L3 length = base_l3_length * M`

This is the first honest test of one fat market instead of `M` separate `L3` pockets.

## Usage

```bash
lua /home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_l2_l3_multiplier_stand/main.lua \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua \
  5
```

Arguments:

1. bootstrap dump `.lua`
2. multiplier `M`
3. optional `L1` ticks, default = `2 * ring`
4. optional `L2/L3` ticks, default = `160`
