# L4 Bootstrap Determines L1 Ring

## Status

Current working hypothesis.

## Main point

`L1 ring` should not be chosen manually for the full machine.

The first `L4` bootstrap prompt should determine the initial active size of `L1`.

## Proposed logic

Cold start:

1. user or system provides a long bootstrap/master prompt
2. frozen `L4` processes this prompt in its early internal layers
3. the resulting early material is taken as-is, without semantic compression
4. this material becomes the basis of `L1`
5. its size determines `ring`
6. `CW` then operates on that ring

## Important rule

The bootstrap determines `ring` only at startup.

Later prompts should **not** resize the ring during normal operation.

## Runtime model

### Cold start

- bootstrap prompt defines the initial `L1` world
- this fixes the active `ring`

### Normal operation

- later user requests do not rebuild `ring`
- later requests inject new dirt / perturbation / language material into the existing `L1`
- the machine continues inside the same world-size

### Soft reset

- `ring` may be rebuilt from a new bootstrap prompt
- world-size may change

### Hard reset

- machine restarts from zero

## Why this is better than dynamic ring per request

If `ring` changed on every user prompt:

- the machine world would constantly change size
- persistence would become unstable
- accumulated `L3` state would lose continuity
- the machine would feel like a series of disconnected runs

If `ring` is bootstrap-defined and then held stable:

- the machine keeps one world-size for one session
- later requests act as perturbations inside that world
- persistence and memory become more coherent

## Interpretation

`ring` should be understood not as "message length", but as:

```text
the size of the current machine world defined at bootstrap
```

## Consequence for the first L4 -> L1 stand

The first honest stand should test:

- bootstrap prompt -> early `L4` material -> `L1 ring`

and only later:

- additional prompts as perturbations into already existing `L1`
