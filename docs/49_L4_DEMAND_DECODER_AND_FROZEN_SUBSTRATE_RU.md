# L4 Demand Decoder And Frozen Substrate

## Status

Current hypothesis.

## Core reading

`L4` is not the core of the machine.

`L4` is:

- `DEMAND`
- manifestation layer
- I/O layer between machine and user
- upper cycle closer
- decoder from internal machine form into external substrate

## Internal vs external role

Inside the stack:

- `L1-L3` are the machine core
- `L4` is the upper service layer

Meaning:

- the machine thinks in `PL / MPL / nanoPL`
- the machine does not need human tokens internally
- human language, code, image, music and similar outputs appear only in `L4`

## zig compatibility

This does not replace zig `TENSION`.

Current reading:

- `L4 internal law` = `TENSION`
- `L4 canonical role` = `DEMAND`

So `L4` is a demand-shaped tension layer.

## Transformer role

`L4` may use an existing transformer or another ready-made external substrate.

Important:

- base `L4` weights stay frozen
- `L4` is replaceable
- the machine core does not retrain `L4` weights during normal work

The machine core should instead condition `L4` at runtime.

## L3 -> L4 hypothesis

`L3` may act as a live adapter for `L4`.

Not full retraining.

More like:

- live conditioning
- live adapter
- live prompt/prefix
- live KV-like memory
- live LoRA-like effect without changing base weights

## L4 -> L1 hypothesis

`L4` may also serve as a large frozen external substrate.

Meaning:

- `L4` stores a large external world, for example a Russian-language transformer
- `L1` does not need to contain this whole world
- `L1` may take active slices / emissions / perturbations from `L4`
- those slices are then chaotized and passed through `L1 -> L2 -> L3`

So `L4` may be both:

- manifestation layer upward
- substrate reservoir downward

## Session model

The machine does not need to tick forever.

Possible mode:

1. load frozen `L3`
2. inject query through `L4`
3. tick `L1-L3`
4. let `L4` manifest result
5. freeze `L3` again

## Consequence

This makes `L4`:

- not the whole model
- not the thinking core
- a frozen replaceable manifest layer over the real machine
