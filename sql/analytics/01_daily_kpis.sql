-- 01_daily_kpis.sql
-- Ежедневные KPI службы поддержки по каналам.
--
-- Задача: один срез «как прошёл день» для руководства и для сверки с дашбордом.
-- Зерно: день × канал.
--
-- Приёмы:
--   * CTE daily считает объёмы с витрины v_interval_volume (уже агрегированной до 30 мин);
--   * CTE asa считает среднее ожидание отвеченных с контактных витрин
--     (у них другое зерно: одно попадание в очередь);
--   * LEFT JOIN склеивает два расчёта по каналу и дню.
--
-- Формулы SL:
--   Голос: handled_in_sl / (handled + abandoned - short_abandoned)
--   Чат и почта: handled_in_sl / entries
-- ASA: среднее wait_sec / wait_answer_sec только по тем, кого взял оператор.

with daily as (
    select channel,
           day,
           sum(entries)            as entries,
           sum(offered)            as offered,
           sum(handled)            as handled,
           sum(abandoned)          as abandoned,
           sum(short_abandoned)    as short_abandoned,
           sum(handled_in_sl)      as handled_in_sl,
           sum(talk_sec)           as talk_sec
    from v_interval_volume
    group by channel, day
),
asa as (
    select 'Голос' as channel,
           cast(wait_start as date) as day,
           avg(case when final_stage = 'operator' then wait_sec end) as asa_sec
    from v_voice_contacts
    group by 2
    union all
    select channel,
           cast(wait_start as date) as day,
           avg(case when is_answered = 1 then wait_answer_sec end) as asa_sec
    from v_text_contacts
    group by 1, 2
)
select d.day,
       d.channel,
       d.entries,
       d.offered,
       d.handled,
       d.abandoned,
       d.short_abandoned,
       case
           when d.channel = 'Голос'
               then round(100.0 * d.handled_in_sl
                          / nullif(d.handled + d.abandoned - d.short_abandoned, 0), 1)
           else round(100.0 * d.handled_in_sl / nullif(d.entries, 0), 1)
       end as sl_pct,
       round(a.asa_sec, 1) as asa_sec
from daily d
left join asa a
  on a.channel = d.channel
 and a.day = d.day
order by d.day, d.channel;
