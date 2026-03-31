# CUDA L3 Substrate Stand

Это тестовый GPU-стенд для `L3 substrate`.

Он нужен, чтобы проверить три вещи:

- что `L3` можно держать на GPU как recurrent substrate
- что crystals могут жить с собственным `pu_stock`
- что `L2 size -> PU_max` можно честно протащить вверх в `L3`

## Что здесь считается

- `L2 size` выводится из `L1 ring/CW`
- `PU_max` берётся как ёмкость `L2`
- crystals приходят с `pu_stock`
- на GPU считается:
  - crystal influence
  - `pu_stock` burn
  - recurrent update клеток

## Запуск

```bash
make
./l3_substrate
./l3_substrate 4096 256 96 12345
./l3_substrate 8192 1024 96 12345
```

Аргументы:

1. `l1_ring`
2. `l1_cw`
3. `ticks`
4. `seed`
