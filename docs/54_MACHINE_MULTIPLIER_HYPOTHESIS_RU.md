# Machine Multiplier Hypothesis

## Status

Current hypothesis.

## Main point

Do not multiply only `L1`.

If scaling is introduced, it should be done through a single explicit machine multiplier:

```text
M = machine multiplier
```

## Proposed scaling law

If `M = x`, then:

- `L1_count = x`
- `L2_count = x`
- `L3_capacity = base_L3 * x`

This means:

- more chaos sources
- more formation factories
- a proportionally fatter market

## Why this is better than multi-L1 alone

If only `L1` is multiplied:

- emission increases
- production does not keep up
- economy risks inflating

If `L1` and `L2` are multiplied together:

- emission grows
- consumption/formation grows too
- price of form does not have to collapse

If `L3` capacity also grows:

- the market has room for increased form volume
- form count grows
- diversity grows
- the machine is less likely to choke on its own output

## Interpretation

`M` should be understood as:

```text
the number of productive machine cores and the proportional market width needed to absorb them
```

## Intended effect

The goal of `M` is not:

- cheaper form
- fake inflation
- duplicated market noise

The goal of `M` is:

- more forms
- more diversity
- larger machine world
- without breaking form price too early

## Important caution

This is still only a hypothesis.

It depends on whether:

- `L2` really consumes enough of increased `L1`
- `L3` can absorb increased output without turning into a dump
- the remaining `PU` at `L3` stays in a reasonable range

## Practical reading

`M = 5` means:

- `5 x L1`
- `5 x L2`
- `5 x L3 market capacity`

Not five separate machines.

One wider machine with five productive lower cores.

## Why it matters

This gives a cleaner scaling knob than arbitrary width increases.

Instead of separately guessing:

- how many `L1`
- how many `L2`
- how much `L3`

the machine can expose one explicit multiplier and then keep its inner proportional law.
