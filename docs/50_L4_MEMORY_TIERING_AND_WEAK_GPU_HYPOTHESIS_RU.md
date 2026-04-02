# L4 Memory Tiering And Weak GPU Hypothesis

## Status

Current hypothesis.

## Main point

`L4` does not need to live in `VRAM`.

Why:

- `L4` is not the constantly ticking core
- `L4` is called on demand
- `L4` may stay frozen
- `L4` may be slower than `L1-L3`

## Proposed hardware split

Fast core:

- `L1`
- `L2`
- `L3`

These should prefer `VRAM`, especially on discrete GPU setups.

Slower upper layer:

- `L4`

This may live in:

- `RAM`
- `NVMe SSD`
- `SATA SSD`
- in extreme cases even slower storage

## Why this matters

This changes scaling.

The system no longer requires:

- "entire large transformer must fit in VRAM"

Instead:

- `VRAM` is used for fast machine core
- `L4` may be much larger than available `VRAM`
- overall size is then limited more by `RAM` or storage than by GPU memory alone

## Practical consequence

This can allow:

- modest GPUs
- older GPUs
- narrow-VRAM setups

to still run a large `L4`-based machine.

The price is:

- slower manifestation latency
- slower cold access
- stronger dependence on storage bandwidth

## Memory ladder

From fastest to slowest:

1. `VRAM`
2. `RAM`
3. `NVMe SSD`
4. `SATA SSD`
5. `HDD`

The hypothesis is not that all of these are equally good.

The hypothesis is that the architecture survives graceful slowdown across this ladder.

## Strong form of the hypothesis

The packet machine may scale not only upward into stronger hardware, but also downward into weaker hardware.

This is possible because:

- the true fast kernel is `L1-L3`
- `L4` can be moved out of the fast memory path
