# Lua L3 Substrate Stand

Это первый честный стенд `L3` как субстрата исполнения с учётом `PU economy`.

Он не является VM.
Он не является трансформером.
Он не делает язык напрямую.

Его задача:

- проверить, может ли `L3` жить как recurrent substrate
- принимать crystals от `L2`
- реагировать на них как на perturbations, а не как на opcodes
- прожигать `pu_stock` кристаллов по тикам
- отдавать устойчивый readout наружу для будущего `L4`

## Идея

`L3` здесь устроен как:

- 1D toroidal tape
- ячейки с активацией
- локальные recurrent связи
- global `CYCLE`
- soft `LOGIC`
- crystal queue
- active crystals
- exhausted pool

Crystal здесь не "инструкция".
Crystal здесь это локальное воздействие на субстрат с конечным `pu_stock`:

- `EXCITE`
- `INHIBIT`
- `CONNECT`
- `RELEASE`

## Что делает тик

На каждом тике:

1. если пришло время, crystal переходит в `active set`
2. каждый активный crystal воздействует на свой участок субстрата
3. каждый активный crystal сжигает часть своего `pu_stock`
4. кристаллы с пустым `pu_stock` уходят в `exhausted pool`
5. `CYCLE` модулирует gain/decay среды
6. каждая клетка считает новый activation из соседей и своих связей
7. `LOGIC` мягко гасит выход за границы
8. readout снимается с выходной зоны
9. если readout устойчив, возникает manifest candidate

## Входы

Стенд принимает параметры `L1`, потому что:

- из `L1` выводится размер `L2`
- из размера `L2` выводится `PU_max`
- из этого уже собирается `L3` как верхний субстрат

```bash
lua main.lua
lua main.lua 4096 256 96 12345
```

Аргументы:

1. `l1_ring`
2. `l1_cw`
3. `ticks`
4. `seed`

## Что печатается

- derived `L2 size`
- derived `PU_max`
- bound/unbound `PU`
- tape length
- crystal schedule
- checkpoint-и по тикам
- средняя энергия субстрата
- readout
- число manifest candidates
- число active/exhausted crystals
- суммарный burned `PU`

## Как читать

Если стенд живой, то должно быть видно:

- разные crystals реально дают разные perturbations
- recurrent substrate не схлопывается мгновенно
- readout меняется не случайно, а в ответ на crystal pattern
- кристаллы не живут вечно, а выгорают
- появляются участки устойчивости, которые уже можно отдавать в `L4`
