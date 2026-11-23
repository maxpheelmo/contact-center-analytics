-- 05_aht_and_agent_ranking.sql
-- AHT по каналу и рейтинг операторов. В файле два запроса, оба выполняются скриптом прогона.
--
-- Запрос A. Среднее время обработки по каналу и дню (витрина v_aht_interval).
--   Голос: разговор + поствызывная (wrap-up).
--   Чат: от распределения на оператора до закрытия, без отсечения по длительности.
--   wrap_found_pct: доля обработанных звонков, к которым нашлась поствызывная.
--   wrap_covered: 1, если за день в хранилище вообще есть статусы (иначе wrap-up нельзя считать).

select channel,
       day,
       sum(handled) as handled,
       round(sum(work_sec) / nullif(sum(handled), 0), 1) as work_sec_avg,
       round(sum(wrap_sec) / nullif(sum(handled), 0), 1) as wrap_sec_avg,
       round((sum(work_sec) + sum(wrap_sec)) / nullif(sum(handled), 0), 1) as aht_sec,
       round(100.0 * sum(wrap_found) / nullif(sum(handled), 0), 1) as wrap_found_pct,
       min(wrap_covered) as wrap_covered
from v_aht_interval
group by channel, day
order by day, channel;

-- Запрос B. Рейтинг операторов внутри канала и дня.
--   JOIN контактных витрин со справочником сотрудников.
--   ROW_NUMBER: место по числу ответов.
--   SUM() OVER: доля оператора в ответах команды за этот день и канал.

with agents as (
    select 'Голос' as channel,
           cast(c.wait_start as date) as day,
           c.operator_login,
           count(*) as handled,
           round(avg(c.talk_sec), 1) as handle_sec_avg
    from v_voice_contacts c
    where c.final_stage = 'operator'
      and c.operator_login is not null
    group by 2, 3
    union all
    select t.channel,
           cast(t.wait_start as date) as day,
           t.operator_login,
           count(*) as handled,
           round(avg(extract(epoch from t.finish_time)
                     - extract(epoch from t.answered_time)), 1) as handle_sec_avg
    from v_text_contacts t
    where t.channel = 'Чат'
      and t.is_answered = 1
      and t.operator_login is not null
      and t.finish_time is not null
      and t.answered_time is not null
    group by 1, 2, 3
)
select a.channel,
       a.day,
       a.operator_login,
       coalesce(e.department, '') as department,
       a.handled,
       a.handle_sec_avg,
       round(100.0 * a.handled
             / nullif(sum(a.handled) over (partition by a.channel, a.day), 0), 1)
           as team_share_pct,
       row_number() over (
           partition by a.channel, a.day
           order by a.handled desc, a.operator_login
       ) as rnk
from agents a
left join dim_employees e on e.login = a.operator_login
order by a.channel, a.day, rnk;
