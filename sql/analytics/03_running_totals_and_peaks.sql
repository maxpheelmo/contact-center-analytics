-- 03_running_totals_and_peaks.sql
-- Накопительный итог нагрузки внутри дня и пиковые интервалы.
--
-- Задача: ответить на два вопроса.
--   1) Как объём набирается в течение суток? (running total)
--   2) В какие 30 минут была максимальная нагрузка и какой там был SL?
--
-- Окна:
--   SUM() OVER ... ROWS UNBOUNDED PRECEDING   накопительный итог
--   ROW_NUMBER() OVER (PARTITION BY канал, день ORDER BY entries DESC)
--                                             ранг пика
-- В финале оставляем топ-5 интервалов каждого канала и дня.

with base as (
    select channel,
           day,
           interval_start,
           entries,
           handled,
           abandoned,
           short_abandoned,
           handled_in_sl,
           case
               when channel = 'Голос'
                   then 100.0 * handled_in_sl
                        / nullif(handled + abandoned - short_abandoned, 0)
               else 100.0 * handled_in_sl / nullif(entries, 0)
           end as sl_pct
    from v_interval_volume
),
running as (
    select channel,
           day,
           interval_start,
           entries,
           handled,
           round(sl_pct, 1) as sl_pct,
           sum(entries) over (
               partition by channel, day
               order by interval_start
               rows between unbounded preceding and current row
           ) as entries_running,
           sum(sum(entries)) over (
               partition by channel, day
           ) as entries_day_total,
           row_number() over (
               partition by channel, day
               order by entries desc, interval_start
           ) as peak_rank
    from base
    group by channel, day, interval_start, entries, handled, sl_pct
)
select channel,
       day,
       interval_start,
       entries,
       entries_running,
       entries_day_total,
       round(100.0 * entries_running / nullif(entries_day_total, 0), 1) as running_share_pct,
       sl_pct,
       peak_rank
from running
where peak_rank <= 5
order by channel, day, peak_rank;
