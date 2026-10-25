# 01 — SL / TP catcher

Documentation: [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction) · [HistoryDealSelect](https://www.mql5.com/en/docs/trading/historydealselect) ·
[HistorySelectByPosition](https://www.mql5.com/en/docs/trading/historyselectbyposition) · [Deal properties (DEAL_REASON)](https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties)

**Problem.** A position was closed by Stop Loss or Take Profit while you were away, and nobody told you.

**Solution.** `SLTPCatcher.mq5` listens to `OnTradeTransaction`. On every new deal it selects that deal (`HistoryDealSelect`),
keeps only closing deals with `DEAL_REASON_SL` or `DEAL_REASON_TP`, then finds the opening deal of the position
and prints both deals the same way the terminal's *Deals* tab shows them, via `Alert` and `Print`.
Works for **all symbols and all magic numbers**, so one copy on any chart is enough.

```
SL | GBPUSD | magic 555
05:00:00 | #10 | buy  in  0.06 @ 1.33402 | S/L 1.32798 | T/P 1.33998
12:03:29 | #13 | sell out 0.06 @ 1.33412 | commission 0.00 | swap 0.00 | profit 0.60
```
(our tester run: the stop loss was moved above the entry price, so this SL closed the position in profit; the entry row keeps the original S/L.)

**Install.** `mql5/SLTPCatcher.mq5` → `MQL5/Experts`, compile, drag onto any chart.

## 1.003: our 1.002 caught nothing in the tester

Version 1.002 called `HistorySelectByPosition(trans.position)` and then read the deal by its ticket right away.
`HistorySelectByPosition` returned `true` and the cache held both deals, but `HistoryDealGetInteger(trans.deal, …)` returned **0 with error 4755**
for every deal. `DEAL_ENTRY` was never `DEAL_ENTRY_OUT`, so the EA stayed silent; `DEAL_REASON` 0 is `DEAL_REASON_CLIENT`, which looks like a real answer.
1.003 selects the deal itself first:

```mql5
if(!HistoryDealSelect(trans.deal))       // 1.003: select the closing deal by its ticket
   return;
ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
```

**Our result** (MetaTrader 5 build 6285 Strategy Tester, MetaQuotes-Demo, hedging account, EURUSD M5 + GBPUSD, USDJPY, 2025-10-15, every tick;
test bench `SLTPLab.mq5`, six positions, the lot shows the row number):

| Lot | Symbol | magic | Closed by | Reason |
|---|---|---|---|---|
| 0.01 | EURUSD Buy | 1001 | TP 04:20:25, +1.48 | TP |
| 0.02 | EURUSD Sell | 1002 | SL 04:20:25 (same tick), −3.04 | SL |
| 0.03 | GBPUSD Buy | 777 | TP 05:05:36, +4.41 | TP |
| 0.04 | USDJPY Sell | 0 ("manual") | TP 04:12:36, +3.88 | TP |
| 0.05 | EURUSD Buy | 42 | the EA itself, 06:00 | EXPERT (must be ignored) |
| 0.06 | GBPUSD Buy | 555 | SL moved above entry, 12:03:29, **+0.60** | SL |

| How the deal is read (`InpCatch`) | Caught |
|---|---|
| no history selected, `HistoryDealGetInteger(trans.deal, DEAL_REASON)` | **0 of 5** ✗ — every close: reason CLIENT, error 4755 |
| `HistorySelectByPosition`, then the deal by ticket (= 1.002) | **0 of 5** ✗ — every close: entry 0, reason CLIENT, error 4755 |
| `HistoryDealSelect`, then `DEAL_REASON` (= 1.003) | **5 of 5** ✓, the EA's own close skipped |

We checked this in the Strategy Tester only. If a live account behaves differently for you, please open an issue.

**The rule.** Have a deal ticket? `HistoryDealSelect(ticket)` first, then read its properties. A zero from `HistoryDealGetInteger` is not an answer; check `GetLastError()`.

## How to reproduce

> ⚠️ `SLTPLab` needs a **hedging** account (rows 0.01 and 0.02 are a Buy and a Sell of one symbol) and the symbols EURUSD, GBPUSD, USDJPY.
> Your server time and prices may differ, so the closing times may too; the 0 / 0 / 5 result should not.

1. **Copy and compile.** `mql5/SLTPLab.mq5` → `MQL5/Experts/Lessons/SLTPCatcher/SLTPLab.mq5`, compile in MetaEditor (0 errors, 0 warnings).
2. **Run a test.** Strategy Tester: Expert `Lessons\SLTPCatcher\SLTPLab`, EURUSD, M5, 2025.10.15 – 2025.10.16, every tick, deposit 10000 USD, 1:100.
   Input `InpCatch`: no history · position history (1.002) · `HistoryDealSelect` (1.003).
   Or with the terminal **closed**: `terminal64.exe /config:<full path>\tester_right.ini` (also `tester_nohistory.ini`, `tester_byposition.ini`);
   the ini files expect `MQL5/Experts/Lessons/SLTPCatcher/SLTPLab.ex5`.
3. **Read the Journal.** Wrong modes print `missed deal #… reason = CLIENT, error 4755`; the right one prints `Alert:` and the two deal rows.
   With visual mode on, the chart comment shows the counters and one line per close.

Video: re-shoot in progress — BARABASHKA (EN) / БАРАБАШКА (UA), links coming.

---

## Українською

**Проблема.** Позицію закрив Stop Loss чи Take Profit, поки вас не було, і ніхто не повідомив.

**Рішення.** `SLTPCatcher.mq5` слухає `OnTradeTransaction`: на кожну нову угоду вибирає саме цю угоду (`HistoryDealSelect`),
лишає тільки закриття з `DEAL_REASON_SL` / `DEAL_REASON_TP`, знаходить угоду входу й виводить обидві угоди, як у вкладці *Угоди*, — через `Alert` і `Print`.
Працює по **всіх символах і всіх magic**: досить однієї копії на будь-якому графіку.

**Встановлення.** `mql5/SLTPCatcher.mq5` → `MQL5/Experts`, скомпілювати, перетягнути на графік.

**1.003: наш 1.002 у тестері не ловив нічого.** 1.002 викликав `HistorySelectByPosition` і одразу читав угоду за тікетом:
функція повертала `true`, у кеші були обидві угоди, а `HistoryDealGetInteger(trans.deal, …)` давала **0 і помилку 4755** для кожної угоди.
`DEAL_ENTRY` ніколи не дорівнював `DEAL_ENTRY_OUT`, радник мовчав; а `DEAL_REASON` 0 — це `DEAL_REASON_CLIENT`, схоже на справжню відповідь.
1.003 спершу вибирає саму угоду: `HistoryDealSelect(trans.deal)`.

**Наш результат** (тестер MetaTrader 5 білд 6285, MetaQuotes-Demo, хедж, EURUSD M5 + GBPUSD, USDJPY, 15.10.2025, всі тіки; стенд `SLTPLab.mq5`, шість позицій):
- без вибору історії — **0 з 5** ✗ (кожне закриття: CLIENT, помилка 4755);
- `HistorySelectByPosition`, потім угода за тікетом (= 1.002) — **0 з 5** ✗;
- `HistoryDealSelect` (= 1.003) — **5 з 5** ✓: TP ×3, SL ×2, зокрема SL і TP одним тиком і SL у плюсі (+0.60); закриття самим радником пропущено.
Перевіряли лише в тестері.

**Правило.** Маєте тікет угоди — спершу `HistoryDealSelect(тікет)`, потім властивості. Нуль від `HistoryDealGetInteger` — не відповідь: дивіться `GetLastError()`.

**Як відтворити.**
1. `mql5/SLTPLab.mq5` → `MQL5/Experts/Lessons/SLTPCatcher/`, скомпілювати (0 помилок, 0 попереджень). Потрібен **хедж-рахунок** і символи EURUSD, GBPUSD, USDJPY.
2. Тестер: EURUSD M5, 2025.10.15 – 2025.10.16, всі тіки, 10000 USD, 1:100; параметр `InpCatch`.
   Або при **закритому** терміналі: `terminal64.exe /config:<повний шлях>\tester_right.ini` (а також `tester_nohistory.ini`, `tester_byposition.ini`).
3. У журналі тестера: неправильні режими — `missed deal #… reason = CLIENT, error 4755`, правильний — `Alert:` і два рядки угод.

Відео: перезйомка — БАРАБАШКА (UA) / BARABASHKA (EN), посилання згодом.
