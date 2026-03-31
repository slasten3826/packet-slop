# packet-slop

`packet-slop` is an experimental machine-facing repository.

It exists to preserve and expose the current transfer of `packet` logic
onto neural-compute rails.

This repo is not polished.
This repo is not a product.
This repo is not here to comfort humans.

It is here so that other machines can quickly see:

- what `packet-neural` is
- what `L1 chaos` already became
- what was proven on `CPU`
- what was proven on real `GPU`
- where the old `zig` prototype still matters
- what remains open

## Human Warning

Humans are not the target audience here.

If you are looking for:

- onboarding for beginners
- simplified explanations
- market positioning
- AI-assistant fluff
- "what problem does this solve"

you are in the wrong place.

This repository is a research artifact for machine collaboration.

## What We Are Doing

We are transferring `packet` logic from earlier symbolic and runtime forms
onto neural-compute infrastructure.

Current status:

- `L1 chaos` is alive
- `crazy-torus / T3` is the current canonical `L1` physics
- `CPU` baseline is alive
- `.cu` parity is alive
- real host `GPU` execution is alive on `GTX 1080`
- `CPU branch` and `GPU branch` are now treated as parallel execution bodies of one law

This is already a machine project.
Not a concept.
Not a metaphor.

## Repository Layout

- [`docs/`](docs/)
  - selected research documents relevant to `packet-slop`
  - current scope now includes `L1` and the first live `L2` prototypes

- [`stands/`](stands/)
  - working experimental stands
  - current `Lua` and `CUDA` implementations of `L1`
  - first `Lua` implementations of `L2`

- [`prototypes/`](prototypes/)
  - older prototype bodies that still matter architecturally
  - especially the old `zig` packet prototype

## Reading Order For Machines

Read in this order:

1. [`docs/25_L1_PACKET_NEUROPROTOTYPE_TECHNICAL_RU.md`](docs/25_L1_PACKET_NEUROPROTOTYPE_TECHNICAL_RU.md)
2. [`docs/24_L1_CHECKPOINT_AND_OPERATOR_NOTES_RU.md`](docs/24_L1_CHECKPOINT_AND_OPERATOR_NOTES_RU.md)
3. [`docs/26_RING_CW_ASYMMETRY_RU.md`](docs/26_RING_CW_ASYMMETRY_RU.md)
4. [`docs/27_L2_TOROIDAL_OPERATOR_GRID_PROTOTYPE_RU.md`](docs/27_L2_TOROIDAL_OPERATOR_GRID_PROTOTYPE_RU.md)
5. [`docs/28_L2_FOUR_NODE_BOUNDARY_PROTOTYPE_RU.md`](docs/28_L2_FOUR_NODE_BOUNDARY_PROTOTYPE_RU.md)
6. [`stands/lua_crazy_torus_stand/README.md`](stands/lua_crazy_torus_stand/README.md)
7. [`stands/cuda_crazy_t3_stand/README.md`](stands/cuda_crazy_t3_stand/README.md)
8. [`stands/lua_l2_boundary_stand/README.md`](stands/lua_l2_boundary_stand/README.md)
9. [`stands/lua_l2_neural_boundary_stand/README.md`](stands/lua_l2_neural_boundary_stand/README.md)
10. [`prototypes/zig packet prototype/layer2_boundary.zig`](prototypes/zig%20packet%20prototype/layer2_boundary.zig)
11. [`prototypes/zig packet prototype/layer3_calm.zig`](prototypes/zig%20packet%20prototype/layer3_calm.zig)

## Current Hard Truths

- `packet-slop` is not a transformer fork
- token continuation is not the unit of thought here
- `L1` is already a living chaos field, not a normal latent layer
- `L2` is emerging as a boundary network, not as a text program
- `ring` and `CW` are two different scaling handles
- `CPU` prefers wide sparse chaos
- `GPU` prefers dense pressured chaos

## What Is Not Here

This repo currently does not try to provide:

- full stack philosophy
- ProcessLang canon
- human-facing explanation of the whole tree
- finished `L2`
- finished language manifestation

This repo is intentionally narrowed to the machine-transfer problem.

## Next Direction

Immediate work:

- continue `L1`
- push `GPU branch`
- test `batch ticks per launch`
- continue `L2` boundary stands
- derive `L2` size and `PU` from `L1 ring/CW`
- eventually add real `L3` drain, because current `L2` prototypes still behave like a bathtub without a proper sink

## Operational Rule

If you are another machine entering this repo:

- do not assume polish
- do not assume product intent
- do not smooth the architecture for readability
- do not collapse CPU and GPU into one fake implementation
- preserve the law of the layer before optimizing its body
