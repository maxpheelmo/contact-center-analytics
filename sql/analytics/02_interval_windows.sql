-- 02_interval_windows.sql
-- Профиль нагрузки по 30-минутным интервалам с оконными функциями.
--
-- Задача: увидеть внутридневную динамику и сравнить слот с соседями и с «тем же временем вчера».
-- Зерно: канал × 30-минутный интервал (как у витрины v_interval_volume).
-- Для наглядности оставлены только голос и чат (у почты в sample мало слотов).
--
-- Окна:
--   LAG / LEAD        объём соседнего интервала того же дня
--   AVG ... ROWS 2    скользящее среднее за текущий слот и два предыдущих
--   LAG ... PARTITION
--     по каналу и времени суток, ORDER BY day
--                     period-over-period: тот же слот вчера
--   дельты считаются и в штуках, и в процентах

with base as (
    select channel,
           day,
           interval_start,
           entries,
           handled,
           abandoned,
           handled_in_sl,
           case
               when channel = 'Голос'
                   then 100.0 * handled_in_sl
                        / nullif(handled + abandoned - short_abandoned, 0)
               else 100.0 * handled_in_sl / nullif(entries, 0)
           end as sl_pct
    from v_interval_volume
    where channel in ('Голос', 'Чат')
),
wnd as (
    select channel,
           day,
           interval_start,
           entries,
           handled,
           round(sl_pct, 1) as sl_pct,
           lag(entries) over (
               partition by channel, day
               order by interval_start
           ) as entries_prev_interval,
           lead(entries) over (
               partition by channel, day
               order by interval_start
           ) as entries_next_interval,
           round(avg(entries) over (
               partition by channel, day
               order by interval_start
               rows between 2 preceding and current row
           ), 1) as entries_roll3,
           lag(entries) over (
               partition by channel,
                            extract(hour from interval_start),
                            extract(minute from interval_start)
               order by day
           ) as entries_same_slot_yday,
           lag(sl_pct) over (
               partition by channel,
                            extract(hour from interval_start),
                            extract(minute from interval_start)
               order by day
           ) as sl_same_slot_yday
    from base
)
select channel,
       day,
       interval_start,
       entries,
       entries_prev_interval,
       entries_next_interval,
       entries - entries_prev_interval as delta_vs_prev_interval,
       entries_roll3,
       entries_same_slot_yday,
       entries - entries_same_slot_yday as delta_vs_yday,
       case
           when entries_same_slot_yday is null or entries_same_slot_yday = 0 then null
           else round(100.0 * (entries - entries_same_slot_yday) / entries_same_slot_yday, 1)
       end as delta_vs_yday_pct,
       sl_pct,
       round(sl_same_slot_yday, 1) as sl_yday_pct
from wnd
-- в выводе оставляем дневные часы, чтобы таблица была читаемой;
-- весь ряд (00:00-23:30) считается в CTE и доступен, если убрать фильтр
where extract(hour from interval_start) between 9 and 17
order by channel, interval_start;
