# CUDA Eva.00 Multi-L3 Cost Stand

GPU-стенд для гипотезы:

- несколько независимых `L3`
- `Eva.00 encode core` один и тот же
- цена жизни формы в `L3` падает как `1 / l3_count`

## Что проверяется

- меняется ли lifetime формы на GPU
- различаются ли `L3`-карманы
- растёт ли одновременная живая population

## Запуск

```bash
make
./eva00_multi_l3_gpu
./eva00_multi_l3_gpu 128 1024 12345 5 72
```

Аргументы:

1. `ticks`
2. `process_count`
3. `seed`
4. `l3_count`
5. `l3_length`
