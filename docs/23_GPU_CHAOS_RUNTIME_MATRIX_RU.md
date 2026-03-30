# GPU Chaos Runtime Matrix

Этот документ фиксирует первый настоящий GPU-прогон `L1 chaos`
на хостовой `GTX 1080`.

Важно:

- это уже не sandbox
- это уже не `.cu`-reference на CPU
- это реальный `use_gpu=1`

## Что было проверено

Стенд:

- [cuda_crazy_t3_stand](/home/slasten/dev/packetLearning/stack/packet/cuda_crazy_t3_stand/README.md)

Контрольный прогон:

```bash
./crazy_t3 64 512 12345 3 0 1
```

Что подтвердилось:

- GPU-путь реально исполняется
- поведение совпадает с `Lua T3`
- `carry`, `fingerprint`, `distinct_core`, `distinct_trace` совпали с эталоном

Это значит:

- `L1 law` выдержал перенос на настоящее GPU-исполнение
- первая GPU-ветка признана живой

## Первая GPU-матрица

Ниже приведены ключевые строки из первого host-GPU benchmark.

### ring = 64

- `1 trace -> 5381 us / distinct_core = 30`
- `3 trace -> 5654 us / distinct_core = 43`
- `10 trace -> 5831 us / distinct_core = 44`
- `32 trace -> 5545 us / distinct_core = 44`
- `64 trace -> 5327 us / distinct_core = 39`

### ring = 128

- `1 trace -> 11387 us / distinct_core = 67`
- `3 trace -> 11349 us / distinct_core = 61`
- `10 trace -> 10787 us / distinct_core = 80`
- `32 trace -> 10574 us / distinct_core = 79`
- `64 trace -> 9973 us / distinct_core = 102`
- `128 trace -> 9554 us / distinct_core = 91`

### ring = 256

- `1 trace -> 21119 us / distinct_core = 124`
- `3 trace -> 20546 us / distinct_core = 136`
- `10 trace -> 20896 us / distinct_core = 167`
- `32 trace -> 22009 us / distinct_core = 176`
- `64 trace -> 19483 us / distinct_core = 178`
- `128 trace -> 18864 us / distinct_core = 172`
- `256 trace -> 17960 us / distinct_core = 189`

### ring = 512

- `1 trace -> 41062 us / distinct_core = 184`
- `3 trace -> 40524 us / distinct_core = 267`
- `10 trace -> 40933 us / distinct_core = 325`
- `32 trace -> 41400 us / distinct_core = 372`
- `64 trace -> 35745 us / distinct_core = 379`
- `128 trace -> 35070 us / distinct_core = 410`
- `256 trace -> 33614 us / distinct_core = 366`

### ring = 1024

- `1 trace -> 77584 us / distinct_core = 319`
- `3 trace -> 71473 us / distinct_core = 529`
- `10 trace -> 71473 us / distinct_core = 550`
- `32 trace -> 74875 us / distinct_core = 581`
- `64 trace -> 68287 us / distinct_core = 647`
- `128 trace -> 64169 us / distinct_core = 625`
- `256 trace -> 61182 us / distinct_core = 654`

## Что это значит

GPU ведёт себя не так, как CPU.

На CPU первая матрица выглядела так:

- больше `trace_count` почти прямо увеличивает цену

На GPU уже видно другое:

- на малых кольцах цена почти плоская
- на больших кольцах цена иногда даже падает при росте `trace_count`
- `distinct_core` всё ещё растёт, но уже на другой экономике

Это значит:

- у `CPU L1` и `GPU L1` может быть один закон
- но разное вычислительное тело

Именно поэтому теперь разумно думать о двух ветках:

- `CPU branch` как эталон, отладка, малые стенды
- `GPU branch` как среда для больших полей и другой упаковки тиков

## Пороговые режимы уже видны

После основной матрицы были отдельно проверены пороги вокруг размеров warp и block.

### ring = 1024

- `31 trace -> 86282 us`
- `32 trace -> 76644 us`
- `33 trace -> 69370 us`

- `63 trace -> 67121 us`
- `64 trace -> 75882 us`
- `65 trace -> 67722 us`

- `127 trace -> 63159 us`
- `128 trace -> 63071 us`
- `129 trace -> 60787 us`

- `255 trace -> 63113 us`
- `256 trace -> 63098 us`
- `257 trace -> 70623 us`

### ring = 2048

- `511 trace -> 145723 us`
- `512 trace -> 133541 us`
- `513 trace -> 149729 us`

- `1023 trace -> 142644 us`
- `1024 trace -> 120740 us`
- `1025 trace -> 128662 us`

Что из этого уже видно:

- GPU чувствителен к порогам, а не только к "общему количеству работы"
- точные границы `256`, `512`, `1024` дают отдельные режимы исполнения
- местами добавление одного trace резко ускоряет прогон, а местами резко замедляет

Это значит:

- у GPU есть своя внутренняя топология эффективности
- и `trace_count` уже нельзя рассматривать только как абстрактную ручку богатства поля
- это одновременно и ручка вычислительной формы

## Жёсткий вывод

GPU не просто "ускоряет тот же самый стенд".

GPU уже заставляет думать о другой форме исполнения того же `L1 law`.

То есть первая реальная проверка подтвердила:

- закон слоя переносим
- но инженерное тело слоя для GPU не обязано быть CPU-подобным
