# -*- coding: utf-8 -*-
"""Прогнать примеры из sql/analytics/*.sql на DuckDB и записать docs/analytics_queries.md.

Запуск из корня репозитория (после python py/load_sample.py):

    python sql/analytics/run_examples.py
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "py"))

import wfm_store  # noqa: E402


def split_statements(sql: str) -> list[str]:
    """Разрезать файл на запросы: убрать блочные комментарии -- и /* */, резать по ;."""
    without_block = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    lines = []
    for line in without_block.splitlines():
        if re.match(r"\s*--", line):
            continue
        lines.append(line)
    text = "\n".join(lines)
    parts = []
    for raw in text.split(";"):
        stmt = raw.strip()
        if stmt:
            parts.append(stmt)
    return parts


def df_to_markdown(df: pd.DataFrame) -> str:
    if df.empty:
        return "_Пустой результат._"
    out = df.copy()
    for col in out.columns:
        if col == "day":
            if pd.api.types.is_datetime64_any_dtype(out[col]):
                out[col] = out[col].dt.strftime("%Y-%m-%d")
            else:
                out[col] = out[col].astype(str).str.replace(r" 00:00:00$", "", regex=True)
        elif pd.api.types.is_datetime64_any_dtype(out[col]):
            out[col] = out[col].dt.strftime("%Y-%m-%d %H:%M")
        elif pd.api.types.is_float_dtype(out[col]) or str(out[col].dtype) in {"Int64", "Float64"}:
            def fmt(x, _col=col):
                if x is None or pd.isna(x):
                    return ""
                try:
                    fv = float(x)
                except (TypeError, ValueError):
                    return str(x)
                return str(int(fv)) if fv.is_integer() else f"{fv:.1f}"
            out[col] = out[col].map(fmt)
        elif str(out[col].dtype) == "object":
            out[col] = out[col].apply(lambda x: "" if x is None or pd.isna(x) else x)

    def cell(v):
        if v is None or (not isinstance(v, str) and pd.isna(v)):
            return ""
        s = str(v)
        if s in {"<NA>", "nan", "NaN", "None", "NaT", "<NAT>"}:
            return ""
        return s.replace("|", "\\|")

    cols = [str(c) for c in out.columns]
    header = "| " + " | ".join(cols) + " |"
    sep = "| " + " | ".join("---" for _ in cols) + " |"
    rows = []
    for _, row in out.iterrows():
        cells = [cell(row[c]) for c in out.columns]
        rows.append("| " + " | ".join(cells) + " |")
    return "\n".join([header, sep, *rows])


TITLES = {
    "01_daily_kpis.sql": "Ежедневные KPI по каналам",
    "02_interval_windows.sql": "Профиль интервалов: LAG/LEAD, скользящее среднее, сравнение со вчера",
    "03_running_totals_and_peaks.sql": "Накопительный итог и пиковые интервалы (топ-5)",
    "04_channel_funnel.sql": "Воронка по каналам",
    "05_aht_and_agent_ranking.sql": "AHT по каналу и рейтинг операторов",
    "06_occupancy_from_statuses.sql": "Occupancy по операторам в окне смены",
    "07_data_quality.sql": "Проверки качества данных",
}

SUBTITLES_05 = [
    "A. AHT по каналу и дню",
    "B. Рейтинг операторов",
]


def main() -> int:
    os.chdir(ROOT)
    files = sorted(HERE.glob("0*.sql"))
    if not files:
        print("Не найдены sql/analytics/0*.sql")
        return 1

    sections = [
        "# Результаты аналитических запросов",
        "",
        "Прогон примеров из `sql/analytics/` по синтетическим данным `sample_data/`",
        "(16–17 марта 2026). Это не показатели какой-либо компании.",
        "",
        "Как повторить: `python py/load_sample.py`, затем `python sql/analytics/run_examples.py`.",
        "",
    ]

    con = wfm_store.connect()
    try:
        for path in files:
            print("=" * 72)
            print(path.name)
            statements = split_statements(path.read_text(encoding="utf-8"))
            title = TITLES.get(path.name, path.name)
            sections.append(f"## {path.name}: {title}")
            sections.append("")
            for i, stmt in enumerate(statements, 1):
                df = con.execute(stmt).df()
                print(f"--- statement {i}/{len(statements)} shape={df.shape} ---")
                with pd.option_context("display.width", 200, "display.max_columns", 30, "display.max_rows", 40):
                    print(df)
                if path.name == "05_aht_and_agent_ranking.sql" and i <= len(SUBTITLES_05):
                    sections.append(f"### {SUBTITLES_05[i - 1]}")
                    sections.append("")
                elif len(statements) > 1:
                    sections.append(f"### Запрос {i}")
                    sections.append("")
                # interval window output can be long; keep all, it's the point
                sections.append(df_to_markdown(df))
                sections.append("")
    finally:
        con.close()

    out = ROOT / "docs" / "analytics_queries.md"
    out.write_text("\n".join(sections).rstrip() + "\n", encoding="utf-8")
    print(f"\nЗаписано: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
