# L1-L3 Runbook

Это текущий чистый маршрут запуска рабочей машины.

Не читай весь `stands/`.
Иди по этим шагам.

## 1. Bootstrap

Источник:

- [processlang_bootstrap_machine_ru.txt](/home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru.txt)

Скомпилированный `v2` bootstrap:

- [processlang_bootstrap_machine_ru_v2.txt](/home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.txt)
- [processlang_bootstrap_machine_ru_v2.lua](/home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua)

Это сейчас канонический cold start мира машины.

## 2. Single `L1`

Запуск:

```bash
lua /home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_bootstrap_from_l4_stand/main.lua \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua \
  15930 \
  C
```

Смысл:

- `ring` берётся из transformer bootstrap
- `variant=C` сейчас канон

## 3. `Mx(L1)`

Запуск:

```bash
lua /home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_multiplier_stand/main.lua \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua \
  5
```

Смысл:

- один bootstrap-мир
- `5` параллельных `L1`

## 4. `Mx(L1+L2)`

Запуск:

```bash
lua /home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_l2_multiplier_stand/main.lua \
  /home/slasten/dev/packetLearning/packet-slop/stands/python_l4_to_l1_bootstrap_probe/processlang_bootstrap_machine_ru_v2.lua \
  5
```

Смысл:

- сначала `5 x L1`
- потом у каждого ядра свой `L2`
- текущий грубый мост: `L1 fp -> L2 seed`

## 5. Current `L2 -> L3`

Запуск:

```bash
lua /home/slasten/dev/packetLearning/packet-slop/stands/lua_eva00_l2_l3_stand/main.lua \
  7965 \
  1 \
  160 \
  12345
```

Это не финальный рынок.
Это текущая живая `Eva.00`-сцепка между `FORMATION` и `MARKET`.

## Operational Rule

Если нужна рабочая машина:

- не блуждай по старым прототипам
- не трогай всё подряд
- начинай с этого runbook
