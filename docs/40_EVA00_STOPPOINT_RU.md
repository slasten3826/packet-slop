# Eva.00 Stop Point

Этот документ фиксирует, где работа остановилась на текущий момент.

## Что уже есть

### 1. Eva.00 CPU

Есть связанный CPU-стенд:

- [stands/lua_eva00_l2_l3_stand/main.lua](/home/slasten/dev/packetLearning/packet-slop/stands/lua_eva00_l2_l3_stand/main.lua)

Он проверяет:

- `L2` как граф из 4 типов:
  - `OBSERVE`
  - `CHOOSE`
  - `ENCODE`
  - `RUNTIME`
- `L3` как life-space из:
  - `RUNTIME`
  - `CYCLE`
  - `LOGIC`
  - `MANIFEST`

Стресс-тесты показали:

- малые и средние режимы у `Eva.00 CPU` живые
- большие режимы уводят `L3` в persistent hot field
- `CYCLE` практически не рождается
- слой по характеру сейчас `LOGIC/MANIFEST`-heavy

CPU baseline зафиксирован в:

- [docs/39_EVA00_CPU_BASELINE_RU.md](/home/slasten/dev/packetLearning/packet-slop/docs/39_EVA00_CPU_BASELINE_RU.md)

### 2. Экономические стенды L2 и L2->L3

Есть отдельные стенды:

- [stands/lua_l2_market_cost_stand/main.lua](/home/slasten/dev/packetLearning/packet-slop/stands/lua_l2_market_cost_stand/main.lua)
- [stands/lua_l2_l3_market_flow_stand/main.lua](/home/slasten/dev/packetLearning/packet-slop/stands/lua_l2_l3_market_flow_stand/main.lua)

Они показали:

- `CHAOS` может быть дешёвым
- `CALM` может быть дорогим
- `ENCODE` не просто дорогой сам по себе
- `ENCODE` делает всё после себя дорогим
- `raw`-формы до `L3` доходят
- `calm`-формы доминируют количественно

### 3. L3 как смешанная среда

Зафиксировано, что `L3` уже не выглядит как чистый `CALM`.

Он выглядит как mixed form ontology:

- в нём живут и `raw`, и `calm` формы
- но уже переписанные через онтологию `L2`

Документы:

- [docs/37_L3_MIXED_FORM_ONTOLOGY_RU.md](/home/slasten/dev/packetLearning/packet-slop/docs/37_L3_MIXED_FORM_ONTOLOGY_RU.md)
- [docs/38_L3_TOPOLOGICAL_MODE_BEHAVIOR_RU.md](/home/slasten/dev/packetLearning/packet-slop/docs/38_L3_TOPOLOGICAL_MODE_BEHAVIOR_RU.md)

### 4. Eva.00 GPU

Есть первый GPU-стенд:

- [stands/cuda_eva00_l2_l3_stand/main.cu](/home/slasten/dev/packetLearning/packet-slop/stands/cuda_eva00_l2_l3_stand/main.cu)

Он уже:

- собирается
- запускается на реальной GPU
- считает связку `L2 -> L3`

Проверенные прогоны:

- `1024 / 64 / 64 / 12345`
- `4096 / 256 / 64 / 12345`

Что уже видно:

- `Eva.00 GPU` живой
- он масштабируется в сторону большого active-field
- он ещё сильнее, чем CPU, сваливается в `LOGIC/MANIFEST`
- `CYCLE` в текущем GPU-теле тоже почти отсутствует

## Что подтверждено

### 1. Eva.00 существует как внутренняя проекция

Это уже не пустая идея.

Есть:

- `Eva.00 CPU`
- `Eva.00 GPU`

Обе ветки реально живут как вычислительные тела.

### 2. У Eva.00 есть характер

Сейчас `Eva.00` ведёт себя как:

- сильное рождение форм
- сильный уклон в `LOGIC`
- заметный уклон в `MANIFEST`
- слабый `RUNTIME`
- почти отсутствующий `CYCLE`

### 3. На больших режимах Eva.00 перегревается

И CPU, и GPU уже показали:

- при росте `L1 ring/CW`
- `L3` уходит в слишком устойчивую перегретую популяцию форм

То есть жизнь формы начинает превращаться в persistent field.

## Где мы реально остановились

На данный момент главный следующий вопрос не “работает ли Eva.00”.

Она уже работает.

Главный следующий вопрос:

> как сделать так, чтобы `CYCLE` действительно жил,
> а `L3` не схлопывался в `LOGIC/MANIFEST`-heavy hot field.

## Что делать дальше

Следующий рабочий порядок:

1. Зафиксировать GPU baseline отдельным документом.
2. Свести `Eva.00 CPU` и `Eva.00 GPU` в одну сравнительную таблицу.
3. Подкрутить именно `mode-mapping` и `L3`-физику:
   - вытянуть `CYCLE`
   - ослабить доминацию `LOGIC/MANIFEST`
   - усилить остывание `L3`
4. Только после этого делать следующий большой прогон.

## Самая короткая формула

Сегодня дошли до точки, где:

- `Eva.00 CPU` уже есть
- `Eva.00 GPU` уже есть
- mixed `L3` уже есть
- топологическое поведение режимов уже видно

И главный следующий шаг:

- не придумывать новую абстракцию,
- а дожимать жизнь `CYCLE`
- и душить перегрев формы в `L3`.
