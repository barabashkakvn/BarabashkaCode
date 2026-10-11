# BarabashkaCode

Code for the **BARABASHKA** (English) and **БАРАБАШКА** (Ukrainian) YouTube channels:
short MQL5 episodes — a real problem from the MQL5 forum, why it happens, and how to do it right.
Also: Python + MetaTrader 5 and writing code with AI.

> Educational code, not trading or investment advice.

## Episodes

| # | Episode | What you get |
|---|---|---|
| 01 | [SL / TP catcher](episodes/01-sl-tp-catcher/) | EA that alerts on every position closed by Stop Loss or Take Profit (any symbol, any magic) |
| 04 | [Invalid volume](episodes/04-invalid-volume/) | Correct lot normalization (MIN / MAX / STEP / LIMIT) and a script that compares wrong vs right |

Numbers match the videos; a gap means that number was not a code episode.

## How to use

Copy the `.mq5` / `.mqh` files of an episode into your terminal's `MQL5` folder
(*File → Open Data Folder* in MetaTrader 5): Expert Advisors into `MQL5/Experts`,
scripts into `MQL5/Scripts`; keep an `.mqh` next to the file that includes it. Compile in MetaEditor.

## Related

[ProbLab](https://github.com/barabashkakvn/ProbLab) — an open lab: what statistics says about trading ideas.

---

## Українською

Код до YouTube-каналів **БАРАБАШКА** (українською) і **BARABASHKA** (англійською):
короткі випуски про MQL5 — реальна проблема з форуму MQL5, чому так стається і як правильно.
А також Python + MetaTrader 5 і код за допомогою ШІ.

> Навчальний код, а не торгові чи інвестиційні поради.

| № | Випуск | Що всередині |
|---|---|---|
| 01 | [SL / TP catcher](episodes/01-sl-tp-catcher/) | радник: Alert на кожне закриття позиції по Stop Loss або Take Profit (усі символи, усі magic) |
| 04 | [Invalid volume](episodes/04-invalid-volume/) | правильна нормалізація лота (MIN / MAX / STEP / LIMIT) і скрипт «неправильно / правильно» |

Як користуватись: скопіюйте файли випуску в теку `MQL5` терміналу (*Файл → Відкрити каталог даних*):
радники — у `MQL5/Experts`, скрипти — у `MQL5/Scripts`, `.mqh` — поруч із файлом, що його підключає. Скомпілюйте в MetaEditor.

## Author / Автор

Volodymyr Karputov ([MQL5 profile](https://www.mql5.com/en/users/barabashkakvn)).
Built together with Claude (Anthropic) as a coding assistant.

## License

Code — [MIT](LICENSE). Texts and images — [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
