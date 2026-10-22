# 06 — Close all positions: why the loop must go from the end

Documentation: [PositionsTotal](https://www.mql5.com/en/docs/trading/positionstotal) · [OrdersTotal](https://www.mql5.com/en/docs/trading/orderstotal) ·
[ObjectsTotal](https://www.mql5.com/en/docs/objects/objectstotal) · [ArrayRemove](https://www.mql5.com/en/docs/array/arrayremove)

**Problem.** The EA had to close all five positions. The loop finished, and two positions stayed open.

**Why.** Positions are a list with indexes `0 … PositionsTotal() - 1`. Once the position at index `i` is closed,
every position above it shifts down by one and `PositionsTotal()` decreases. `i++` jumps over the position that has just moved into the free slot.

| i | PositionsTotal() | closed | left (lots) |
|---|---|---|---|
| 0 | 5 | 0.01 | 0.02 0.03 0.04 0.05 |
| 1 | 4 | 0.03 | 0.02 0.04 0.05 |
| 2 | 3 | 0.05 | 0.02 0.04 |
| 3 | 2 | — (3 < 2 is false, exit) | **0.02 0.04** ✗ |

```mql5
for(int i = 0; i < PositionsTotal(); i++)        // wrong: every second position is skipped
for(int i = PositionsTotal() - 1; i >= 0; i--)   // right: closing index i shifts only what is already done
```

The same applies to pending orders (`OrdersTotal()`), chart objects (`ObjectsTotal()`) and your own arrays (`ArrayRemove()`).
The symbol and magic filter goes inside the loop; the direction of the loop does not depend on it.

**Our result** (MetaQuotes-Demo, hedging account, EURUSD M5, 2025-10-15, deposit 10,000 USD; one item per hour from 03:00 server time,
lots 0.01 … 0.05, so the lot shows the item's number; one hour after the fifth, all of them are deleted in one loop):

| What is deleted | Loop | Left after the loop |
|---|---|---|
| positions | from 0 | **0.02 and 0.04** ✗ |
| positions | from the end | 0 of 5 ✓ |
| Buy Limit orders | from 0 / from the end | 0.02 and 0.04 ✗ / 0 ✓ |
| buttons on the chart | from 0 / from the end | 0.02 and 0.04 ✗ / 0 ✓ |
| positions + one "manual" (magic 0) | `while(PositionsTotal() > 0)` close index 0 | 0, but the **manual position was closed first** ✗ |
| positions + one "manual" (magic 0) | the same `while` with the symbol and magic filter | our 5 of 5 untouched after **100,000 passes** (our guard): index 0 is never ours, nothing changes, the loop would never end ✗ |
| tickets array, two positions closed "outside the EA" | clean the array from 0 with `ArrayRemove` | 4 tickets for 3 positions ✗ |
| the same | clean the array from the end | 3 tickets = 3 positions, then 0 ✓ |

**The rule.** Removing items from a list or an array in a loop? Go from the end.

## How to reproduce

> ⚠️ Positions need a **hedging** account: on a netting account five buys of one symbol are one position, and the EA refuses to start.
> Your server time and prices may differ; the skipped items (0.02 and 0.04 for the loop from 0) do not.

1. **Copy and compile.** `mql5/CloseLoop.mq5` → `MQL5/Experts/Lessons/CloseLoop/CloseLoop.mq5`, compile in MetaEditor (0 errors, 0 warnings).
2. **Run a test.** Strategy Tester: Expert `Lessons\CloseLoop\CloseLoop`, EURUSD, M5, 2025.10.15 – 2025.10.16, deposit 10000 USD, 1:100.
   Choose the inputs:

   | Input | Values |
   |---|---|
   | `InpLoop` (Delete loop) | from 0 · from the end · while (no filter) · while + filter · tickets array cleaned from 0 · from the end (`while` and the array: positions only) |
   | `InpTarget` (What to delete) | positions · pending orders (Buy Limit far below the price) · chart objects (buttons) |
   | `InpManual` | one "manual" position (magic 0, 0.10 lot) first: for the `while` tests |
   | `InpStartHour` | first item not before this hour, server time (3: the spread is wide at night) |

   Or with the terminal **closed**, one of the 10 configs (it starts, tests and shuts down):
   `terminal64.exe /config:<full path>\tester_positions_wrong.ini` (also `_right`, `_while`, `_whilefilter`, `_arraywrong`, `_arrayright`,
   `tester_orders_wrong/right.ini`, `tester_objects_wrong/right.ini`). The ini files expect `MQL5/Experts/Lessons/CloseLoop/CloseLoop.ex5`.
3. **Read the Journal.** The EA prints every step of the loop and the result, for example:
   ```
   After the loop: 2 of 5 positions left, PositionsTotal() = 2
   ```
   With visual mode on, the chart comment shows the list with indexes, and for the tickets array every ticket and "no such position".

Video: [БАРАБАШКА (UA)](https://youtu.be/37sYYVO4mh8) · EN — coming soon

---

## Українською

**Проблема.** Радник мав закрити всі п'ять позицій. Цикл пройшов, а дві позиції лишились.

**Чому.** Позиції — це список з індексами `0 … PositionsTotal() - 1`. Після закриття позиції з індексом `i` усі позиції вище зсуваються на один вниз,
а `PositionsTotal()` меншає. `i++` перестрибує позицію, яка щойно сіла на звільнене місце.

```mql5
for(int i = 0; i < PositionsTotal(); i++)        // неправильно: пропускає кожну другу
for(int i = PositionsTotal() - 1; i >= 0; i--)   // правильно: з кінця
```

Те саме — для відкладених ордерів (`OrdersTotal()`), об'єктів на графіку (`ObjectsTotal()`) і ваших масивів (`ArrayRemove()`).
Фільтр за символом і magic — усередині циклу; напрям циклу від нього не залежить.

**Наш результат** (MetaQuotes-Demo, хедж-рахунок, EURUSD M5, 15.10.2025, щогодини з 03:00 за сервером, лоти 0.01 … 0.05):
- позиції, ордери Buy Limit, кнопки на графіку: цикл від 0 лишає **0.02 і 0.04** ✗, з кінця — 0 ✓;
- `while(PositionsTotal() > 0)` без фільтра першою закрив **чужу** позицію (magic 0) ✗;
- `while` з фільтром: 100 000 проходів (наш запобіжник), наші 5 з 5 на місці — без запобіжника цикл не закінчився б ✗;
- масив тікетів, дві позиції закрито «ззовні»: чистка від 0 — 4 тікети на 3 позиції ✗, з кінця — 3 = 3 ✓.

**Правило.** Видаляєте зі списку чи масиву в циклі — йдіть з кінця.

**Як відтворити.**
1. `mql5/CloseLoop.mq5` → `MQL5/Experts/Lessons/CloseLoop/`, скомпілювати (0 помилок, 0 попереджень). Для позицій потрібен **хедж-рахунок**.
2. Тестер: EURUSD M5, 2025.10.15 – 2025.10.16, 10000 USD, 1:100; параметри `InpLoop` (як видаляти) і `InpTarget` (що видаляти), для `while` — `InpManual = true`.
   Або при **закритому** терміналі: `terminal64.exe /config:<повний шлях>\tester_positions_wrong.ini` (усього 10 конфігів).
3. У журналі тестера — кожен крок циклу і підсумок, наприклад `After the loop: 2 of 5 positions left`.

Відео: [БАРАБАШКА (UA)](https://youtu.be/37sYYVO4mh8) · EN — скоро
