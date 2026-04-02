# L1-L3 State

Текущий рабочий статус ядра:

- `L1` живой через transformer bootstrap
- `L1(C)` канон
- `ProcessLang DSL -> compiler(v2) -> paradox` даёт жирный bootstrap
- текущий канонический bootstrap даёт `ring ~= 7965`
- `Mx(L1)` уже живой
- `Mx(L1+L2)` уже живой в грубой версии
- `L2 -> L3` живёт в `Eva.00`, но пока ещё не является финальным `MARKET`
- `L3 -> dynamic LoRA -> frozen L4` технически уже живой
- baseline-vs-adapted тест на `Paradox` и base `Llama` не дал сдвига
- узкое место сейчас локализовано в физике `L3`, а не в `L4`

## Current Hard Truths

- `stands/` больше нельзя читать как чистую рабочую поверхность
- `stands/` теперь архив исследований и быстрых probes
- рабочий контур надо читать отдельно через [README.md](/home/slasten/dev/packetLearning/packet-slop/machine_core_l1_l3/README.md)

## Next Refactor Direction

Следующий шаг уже не философский:

- собирать `L1-L3` как отдельное тело
- держать `stands/` как архив
- перестать использовать весь репозиторий как одну свалку
- ответить на главный открытый вопрос:
  - какое у `L3` должно быть техническое тело
