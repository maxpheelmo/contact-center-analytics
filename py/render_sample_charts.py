# -*- coding: utf-8 -*-
"""Картинки для README и docs/dashboards.md по синтетическим данным.

Запуск из корня (после python py/load_sample.py):

    python py/render_sample_charts.py

Нужен matplotlib (в requirements.txt не входит: картинки уже сохранены в docs/img/).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import pandas as pd

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
os.chdir(ROOT)

import wfm_store  # noqa: E402

OUT = ROOT / "docs" / "img"
OUT.mkdir(parents=True, exist_ok=True)

COLORS = {"Голос": "#2F5D8A", "Чат": "#C56A3A", "Почта": "#3D8B6E"}
CAPTION = "Синтетические данные, 16–17 марта 2026. Не являются показателями реальной компании."


def style():
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "axes.titlesize": 13,
        "axes.labelsize": 10,
        "xtick.labelsize": 9,
        "ytick.labelsize": 9,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.color": "#E2E6EA",
        "grid.linewidth": 0.8,
        "figure.facecolor": "white",
        "axes.facecolor": "white",
        "axes.edgecolor": "#8A93A0",
        "text.color": "#1F2933",
        "axes.labelcolor": "#1F2933",
        "xtick.color": "#1F2933",
        "ytick.color": "#1F2933",
    })


def footer(fig, text=CAPTION):
    fig.text(0.5, 0.02, text, ha="center", va="bottom", fontsize=8, color="#5B6470")


def save(fig, name):
    path = OUT / name
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print("wrote", path)


def chart_volume(con):
    df = con.execute("""
        select channel, date_trunc('hour', interval_start) as hour,
               sum(entries) as entries
        from v_interval_volume
        where channel in ('Голос', 'Чат')
        group by 1, 2
        order by 2, 1
    """).df()
    df["hour"] = pd.to_datetime(df["hour"])
    fig, ax = plt.subplots(figsize=(11, 4.6))
    for ch, g in df.groupby("channel"):
        ax.plot(g["hour"], g["entries"], color=COLORS[ch], label=ch, linewidth=2)
    ax.set_title("Почасовая нагрузка: обращения, дошедшие до рабочей очереди")
    ax.set_ylabel("Обращения в час")
    ax.legend(frameon=False)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%d.%m %H:%M"))
    ax.xaxis.set_major_locator(mdates.HourLocator(interval=4))
    fig.autofmt_xdate()
    fig.subplots_adjust(bottom=0.22)
    footer(fig)
    save(fig, "volume_hourly.png")


def chart_sl(con):
    df = con.execute("""
        select channel, date_trunc('hour', interval_start) as hour,
               case
                   when channel = 'Голос'
                       then 100.0 * sum(handled_in_sl)
                            / nullif(sum(handled) + sum(abandoned) - sum(short_abandoned), 0)
                   else 100.0 * sum(handled_in_sl) / nullif(sum(entries), 0)
               end as sl_pct
        from v_interval_volume
        where channel in ('Голос', 'Чат')
        group by 1, 2
        order by 2, 1
    """).df()
    df["hour"] = pd.to_datetime(df["hour"])
    fig, ax = plt.subplots(figsize=(11, 4.6))
    for ch, g in df.groupby("channel"):
        ax.plot(g["hour"], g["sl_pct"], color=COLORS[ch], label=ch, linewidth=2)
    ax.axhline(80, color="#8A93A0", linestyle="--", linewidth=1, label="Ориентир 80%")
    ax.set_ylim(0, 105)
    ax.set_title("Service Level по часам")
    ax.set_ylabel("SL, %")
    ax.legend(frameon=False, loc="lower right")
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%d.%m %H:%M"))
    ax.xaxis.set_major_locator(mdates.HourLocator(interval=4))
    fig.autofmt_xdate()
    fig.subplots_adjust(bottom=0.22)
    footer(fig)
    save(fig, "service_level_hourly.png")


def chart_funnel_aht(con):
    funnel = con.execute("""
        select
            'Чат, 16–17 марта' as period,
            sum(sessions) as sessions,
            sum(sessions_via_bot) as via_bot,
            sum(reached_queue) as reached_queue,
            sum(answered_queue) as answered
        from v_chat_sessions_interval
    """).df().iloc[0]
    aht = con.execute("""
        select channel,
               (sum(work_sec) + sum(wrap_sec)) / nullif(sum(handled), 0) as aht_sec
        from v_aht_interval
        group by channel
        order by channel
    """).df()

    fig, axes = plt.subplots(1, 2, figsize=(11, 4.8))

    labels = ["Сессии входа", "Дошли до очереди", "Ответил оператор"]
    values = [funnel.sessions, funnel.reached_queue, funnel.answered]
    colors = ["#2F5D8A", "#4F7AA8", "#3D8B6E"]
    axes[0].barh(labels[::-1], list(values)[::-1], color=list(colors)[::-1])
    for y, v in enumerate(list(values)[::-1]):
        axes[0].text(v + max(values) * 0.02, y, f"{int(v)}", va="center", fontsize=9)
    bot_pct = 100.0 * funnel.via_bot / funnel.sessions
    axes[0].set_title("Воронка чата")
    axes[0].set_xlabel("Сессии")
    axes[0].text(
        0.0, -0.18,
        f"Через чат-бот: {int(funnel.via_bot)} сессий ({bot_pct:.0f}% входа). В sample все сессии доходят до очереди.",
        transform=axes[0].transAxes, fontsize=8, color="#5B6470",
    )

    axes[1].bar(aht["channel"], aht["aht_sec"], color=[COLORS[c] for c in aht["channel"]])
    for x, v in enumerate(aht["aht_sec"]):
        axes[1].text(x, v + 8, f"{v:.0f} с", ha="center", fontsize=9)
    axes[1].set_title("AHT по каналу")
    axes[1].set_ylabel("Секунды")

    fig.subplots_adjust(bottom=0.18, wspace=0.35)
    footer(fig)
    save(fig, "funnel_and_aht.png")


def main():
    style()
    con = wfm_store.connect()
    try:
        chart_volume(con)
        chart_sl(con)
        chart_funnel_aht(con)
    finally:
        con.close()
    print("Готово:", OUT)


if __name__ == "__main__":
    raise SystemExit(main())
