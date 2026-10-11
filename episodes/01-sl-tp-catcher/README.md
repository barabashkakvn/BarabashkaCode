# 01 — SL / TP catcher

**Problem.** A position was closed by Stop Loss or Take Profit while you were away, and nobody told you.

**Solution.** `SLTPCatcher.mq5` listens to `OnTradeTransaction`. On every new deal it loads the position history
(`HistorySelectByPosition`), keeps only closing deals with `DEAL_REASON_SL` or `DEAL_REASON_TP`,
and prints the entry and exit deals the same way the terminal's *Deals* tab shows them — via `Alert` and `Print`.
Works for **all symbols and all magic numbers**, so one copy on any chart is enough.

```
TP | EURUSD | magic 1001
2026.10.01 10:15:03 | #12345678 | buy  in  0.10 @ 1.08500 | S/L 1.08300 | T/P 1.08900
2026.10.01 14:42:10 | #12345690 | sell out 0.10 @ 1.08900 | commission -0.70 | swap 0.00 | profit 40.00
```

**Install.** `mql5/SLTPCatcher.mq5` → `MQL5/Experts`, compile, drag onto any chart.

Video: BARABASHKA (EN) / БАРАБАШКА (UA) — links coming.

---

## Українською

**Проблема.** Позицію закрив Stop Loss чи Take Profit, поки вас не було, і ніхто не повідомив.

**Рішення.** `SLTPCatcher.mq5` слухає `OnTradeTransaction`: на кожну нову угоду бере історію позиції,
лишає тільки закриття з `DEAL_REASON_SL` / `DEAL_REASON_TP` і виводить угоди входу й виходу, як у вкладці *Угоди*, — через `Alert` і `Print`.
Працює по **всіх символах і всіх magic**: досить однієї копії на будь-якому графіку.

**Встановлення.** `mql5/SLTPCatcher.mq5` → `MQL5/Experts`, скомпілювати, перетягнути на графік.
