"""GuardLab: the same day in two tester modes on one chart.

Reads Common\\Files\\GuardLab_EURUSD_{ohlc,ticks}.csv (written by GuardLab.mq5)
and saves images/guard_compare.png.
"""
import os
from pathlib import Path
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

COMMON = Path(os.environ["APPDATA"]) / "MetaQuotes" / "Terminal" / "Common" / "Files"
OUT = Path(__file__).resolve().parent.parent / "images" / "guard_compare.png"
ERR, OK, REF, TXT, BG = "#D55E00", "#009E73", "#0072B2", "#14213D", "#EEF4FB"


def load(mode):
    df = pd.read_csv(COMMON / f"GuardLab_EURUSD_{mode}.csv")
    df["t"] = pd.to_datetime(df["time_msc"], unit="ms")
    df["loss"] = df["start"] - df["equity"]
    return df


ohlc, ticks = load("ohlc"), load("ticks")
limit = ticks["limit"].iloc[0]
fig, ax = plt.subplots(figsize=(12.8, 7.2), dpi=100)
fig.patch.set_facecolor(BG)
ax.set_facecolor("white")
ax.plot(ticks["t"], ticks["loss"], color=REF, lw=1, label="Every tick based on real ticks")
ax.plot(ohlc["t"], ohlc["loss"], color=ERR, lw=1.5, marker="o", ms=4, label="1 minute OHLC (4 points per minute)")
ax.axhline(limit, color=TXT, ls="--", lw=1)
ax.text(ohlc["t"].iloc[0], limit + 25, f"limit {limit:.0f} USD", color=TXT)
for df, col, mark in ((ticks, OK, "✓"), (ohlc, ERR, "✗")):
    hit = df.iloc[-1]
    ax.scatter([hit["t"]], [hit["loss"]], s=120, color=col, zorder=5)
    ax.annotate(f"{mark} closed at {hit['loss']:.0f} USD = {100 * hit['loss'] / limit:.0f}% of limit",
                (hit["t"], hit["loss"]), xytext=(-260, 10), textcoords="offset points", color=col, fontsize=12)
ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
ax.set_title("EURUSD 2025-04-11, Sell 1 lot at 03:00, loss guard 500 USD", color=TXT)
ax.set_ylabel("loss, USD", color=TXT)
ax.legend(loc="upper left")
ax.grid(alpha=0.3)
OUT.parent.mkdir(exist_ok=True)
fig.tight_layout()
fig.savefig(OUT, facecolor=BG)
print(OUT, len(ohlc), len(ticks))
