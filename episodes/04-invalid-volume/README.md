# 04 — Invalid volume: how to normalize a lot

Forum thread: [Validation failed [Invalid Volume]](https://www.mql5.com/en/forum/498379) ·
checks from the article [«Какие проверки должен пройти торговый робот перед публикацией в Маркете»](https://www.mql5.com/ru/articles/2555)

**Problem.** An EA opens a trade but cannot close it: hundreds of `[Invalid volume]` lines and a log of 2 GB during Market validation.

**Why.** Typical home-made lot "protection" breaks the volume:

| Mistake | Request | Result |
|---|---|---|
| `MathRound(lots/step)*step` — rounds to the nearest step, can go **up** | 0.25 (step 0.1) | 0.30 |
| guessing the step: `if(step==0.01) lots = …*0.1` | 0.05 (step 0.01) | 0.10, risk ×2 |
| `MathMax(lots, min)` after a check returned 0 (“do not trade”) | 0 | 0.01, trade is sent anyway |
| `NormalizeDouble(lots, 2)` | 0.004 (step 0.001) | 0.00 → **Invalid volume** |

**How to do it right** (`mql5/VolumeTools.mqh`):

```mql5
lots = MathMin(lots, max);                     // cut by SYMBOL_VOLUME_MAX (and LIMIT)
lots = MathFloor(lots / step + 1e-7) * step;   // round DOWN to the step
if(lots < min) return 0.0;                     // below the minimum: do not trade
```

- `VolumeSpecGet()` — MIN / MAX / STEP / LIMIT from the server, never guessed.
- `LotNormalize(spec, lots, used)` — the three lines above; digits come from the step. `1e-7` protects from `0.29/0.01 = 28.999…`.
- `CheckVolumeValue()` — final check before `OrderSend` (as in article 2555).
- `VolumeUsed()` — positions + pending orders on the symbol, for `SYMBOL_VOLUME_LIMIT`.
- Close a position with its own volume: `trade.PositionClose(ticket)`.

**Try it.** `mql5/VolumeLab.mq5` + `VolumeTools.mqh` → `MQL5/Scripts`, compile, run on any chart.
Nothing is traded; the journal shows the same requests through the wrong and the right calculation,
plus a row for the chart symbol with its real server properties.

Video: BARABASHKA (EN) / БАРАБАШКА (UA) — links coming.

---

## Українською

**Проблема.** Радник відкриває угоду, а закрити не може: сотні рядків `[Invalid volume]` і лог на 2 ГБ під час перевірки Market.

**Чому.** Саморобний «захист» лота ламає обсяг: `MathRound` округлює вгору, вгаданий крок 0.1 подвоює ризик,
`MathMax(lots, min)` перетворює «не торгуй» (0) на мінімальний лот, `NormalizeDouble(lots, 2)` обнуляє лот із кроком 0.001.

**Як правильно.** Обрізати по максимуму, округлити **вниз** до кроку, менше мінімуму — повернути 0 і не торгувати.
Властивості символу брати з сервера, не вгадувати. Закривати позицію її власним обсягом: `trade.PositionClose(ticket)`.

**Спробувати.** `mql5/VolumeLab.mq5` і `VolumeTools.mqh` → `MQL5/Scripts`, скомпілювати, запустити на графіку.
Скрипт нічого не торгує: у журналі ті самі запити через неправильний і правильний розрахунок.
