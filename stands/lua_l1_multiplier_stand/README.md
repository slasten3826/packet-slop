# lua_l1_multiplier_stand

First rough `multi-L1` stand.

Purpose:

- take one transformer-derived bootstrap dump
- instantiate `M` parallel `L1` cores
- run the canonical `C` chaos law on each core
- compare individual and merged fingerprints

## Current initialization

All cores use the same bootstrap source, but each core is slightly shifted:

- token ring is rotated by core index
- initial carry is biased by core index

This is not final machine law.

It is only a first rough way to avoid five perfectly identical deterministic copies.

## Usage

```bash
lua /home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_multiplier_stand/main.lua \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua \
  5
```

Arguments:

1. bootstrap dump `.lua`
2. multiplier `M`
3. optional ticks, default = `2 * ring`
