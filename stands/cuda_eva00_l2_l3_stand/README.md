# CUDA Eva.00 L2-L3 Stand

Первый GPU-body для `Eva.00`.

Это не канон и не parity-proof.
Это первая честная попытка дать `Eva.00` отдельное тело на `CUDA`.

## Что здесь есть

- `L2` на GPU как hex-grid из:
  - `OBSERVE`
  - `CHOOSE`
  - `ENCODE`
  - `RUNTIME`
- `L3` на GPU как life-space из:
  - `RUNTIME`
  - `CYCLE`
  - `LOGIC`
  - `MANIFEST`

Хост здесь нужен только чтобы:

- собрать spawn candidates из `L2`
- превратить их в кристаллы
- снять метрики

## Что проверяется

- держит ли `Eva.00` ту же внутреннюю проекцию на GPU
- как ведёт себя `L2 -> L3` под параллельным телом
- повторяется ли CPU-перегрев
- как меняется active/exhausted population

## Запуск

```bash
make
./eva00_gpu
./eva00_gpu 4096 256 128 12345
```

Аргументы:

1. `l1_ring`
2. `l1_cw`
3. `ticks`
4. `seed`
