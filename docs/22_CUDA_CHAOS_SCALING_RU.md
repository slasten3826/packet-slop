# 22. CUDA Chaos Scaling

Этот документ фиксирует первую матрицу масштабирования
для `.cu`-стенда `L1 chaos`.

Пока это ещё не настоящий CUDA-kernel path.

Но это уже полезный измерительный слой,
потому что можно варьировать:

- размер кольца
- число `crazy-trace`

и смотреть:

- время
- `distinct_core`
- `distinct_trace`

## Что гонялось

Матрица:

- `ring = 64, 128, 256, 512, 1024`
- `ticks = ring * 8`
- `seed = 12345`
- `traces = 1, 3, 10, 32, 64, 128, 256`

Снимались:

- `elapsed_us`
- `distinct_core`
- `distinct_trace`

## Показательные результаты

### `ring = 64`

- `1 trace  -> 62 us,  distinct_core=30`
- `3 traces -> 186 us, distinct_core=43`
- `10 traces -> 639 us, distinct_core=44`
- `32 traces -> 2159 us, distinct_core=44`
- `64 traces -> 4183 us, distinct_core=39`

### `ring = 128`

- `1 trace  -> 152 us, distinct_core=67`
- `3 traces -> 391 us, distinct_core=61`
- `10 traces -> 1722 us, distinct_core=80`
- `32 traces -> 4261 us, distinct_core=79`
- `64 traces -> 8396 us, distinct_core=102`
- `128 traces -> 16093 us, distinct_core=91`

### `ring = 256`

- `1 trace  -> 254 us, distinct_core=124`
- `3 traces -> 878 us, distinct_core=136`
- `10 traces -> 2772 us, distinct_core=167`
- `32 traces -> 8172 us, distinct_core=176`
- `64 traces -> 15985 us, distinct_core=178`
- `128 traces -> 32697 us, distinct_core=172`
- `256 traces -> 63965 us, distinct_core=189`

### `ring = 512`

- `1 trace  -> 497 us, distinct_core=184`
- `3 traces -> 1520 us, distinct_core=267`
- `10 traces -> 5082 us, distinct_core=325`
- `32 traces -> 15987 us, distinct_core=372`
- `64 traces -> 32130 us, distinct_core=379`
- `128 traces -> 63945 us, distinct_core=410`
- `256 traces -> 128794 us, distinct_core=366`

### `ring = 1024`

- `1 trace  -> 990 us, distinct_core=319`
- `3 traces -> 3000 us, distinct_core=529`
- `10 traces -> 9955 us, distinct_core=550`
- `32 traces -> 31934 us, distinct_core=581`
- `64 traces -> 64325 us, distinct_core=647`
- `128 traces -> 128412 us, distinct_core=625`
- `256 traces -> 256081 us, distinct_core=654`

## Что это показывает

### 1. Время растёт почти линейно по числу traces

Это ожидаемо:

- больше traces
- больше работы на каждом тике

И пока поведение очень похоже на:

- `O(ring * ticks * traces)`

что для текущего стенда нормально.

### 2. Богатство поля растёт нелинейно

`distinct_core` растёт с увеличением traces,
но не бесконечно и не гладко.

Видно:

- на малых кольцах traces быстро упираются в потолок
- на средних и больших кольцах рост дольше даёт сигнал
- после некоторого уровня traces может начаться плато или откат

### 3. `T3` остаётся хорошим baseline

Почему:

- он даёт сильный скачок richness относительно `1`
- он ещё дешёвый по времени
- он легче читается, чем тяжёлые многотрейсные режимы

### 4. Большие trace-count полезны как stress-mode

`10`, `32`, `64+` уже выглядят
не как канон,
а как режимы давления на `chaos-core`.

Они полезны:

- для изучения пределов
- для проверки насыщения
- для понимания, где рост мощности перестаёт быть выгодным

## Текущий вывод

На текущем шаге у `L1 chaos` уже видны две независимые ручки мощности:

- размер поля (`ring`)
- число `crazy-trace`

И они дают разный эффект:

- `ring` увеличивает ёмкость среды
- `trace-count` увеличивает давление жизни на среду

Это уже полезная карта будущей архитектуры.
