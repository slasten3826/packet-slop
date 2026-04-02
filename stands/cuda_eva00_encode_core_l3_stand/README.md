# CUDA Eva.00 Encode Core + L3 Stand

Это `GPU`-тело для той же связки, что уже работает на `CPU`:

- `L1 chaos`
- `L2 microcore around ENCODE`
- текущий `L3` life-space

Здесь нет старого hex-grid `L2`.
Здесь именно `Eva.00 encode core`, перенесённый на `CUDA`.

## Что здесь есть

- много параллельных `EncodeProcess` на устройстве
- hidden `CONNECT` внутри `ENCODE`
- реактивные `OBSERVE` и `CHOOSE`
- `RUNTIME` как редкий gate
- эмиссия crystal в текущий `L3`
- `L3` на тех же 4 режимах:
  - `RUNTIME`
  - `CYCLE`
  - `LOGIC`
  - `MANIFEST`

## Что проверяется

- сохранится ли характер `Eva.00 CPU` на `GPU`
- как `GPU` переварит событийное `ENCODE`-ядро
- изменится ли распределение `L3`-режимов
- останется ли жизнь формы короткой или станет другой

## Запуск

```bash
make
./eva00_encode_gpu
./eva00_encode_gpu 128 1024 12345 72
```

Аргументы:

1. `ticks`
2. `process_count`
3. `seed`
4. `l3_length`
