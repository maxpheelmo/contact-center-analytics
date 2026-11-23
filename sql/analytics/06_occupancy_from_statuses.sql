-- 06_occupancy_from_statuses.sql
-- Occupancy и Utilization по оператору и дню из журнала статусов и разговоров.
--
-- Важно про sample: статус ready записан как «конверт смены» 09:00-17:00, а wrapup
-- лежит внутри этого конверта. Складывать секунды всех статусов нельзя, они пересекаются.
-- Поэтому:
--   staffed_sec     длительность ready за день (время в смене);
--   talk_sec        сумма разговоров, попавших в окно 09:00-17:00;
--   wrap_sec        сумма wrapup внутри того же окна;
--   Occupancy       (talk + wrap) / staffed;
--   Utilization     (talk + wrap) / staffed, в этой постановке совпадает с Occupancy,
--                   потому что в sample нет отдельного статуса «перерыв / обед».
--                   В рабочей модели Utilization обычно считают от запланированного
--                   времени смены, а Occupancy от времени «на линии» (без перерывов).
--
-- Окна:
--   LEAD(entered) OVER (PARTITION BY login ORDER BY entered)  следующий статус
--   используется как страховка, если leaved пустой (в sample он заполнен).

with statuses as (
    select login,
           status,
           entered,
           coalesce(
               leaved,
               lead(entered) over (partition by login order by entered)
           ) as ended,
           extract(epoch from coalesce(
               leaved,
               lead(entered) over (partition by login order by entered)
           ) - entered) as dur_sec
    from agent_status_changes
),
shift as (
    select login,
           cast(entered as date) as day,
           sum(dur_sec) as staffed_sec
    from statuses
    where lower(status) = 'ready'
      and dur_sec is not null
      and dur_sec >= 0
    group by 1, 2
),
wrap as (
    select login,
           cast(entered as date) as day,
           sum(dur_sec) as wrap_sec
    from statuses
    where lower(status) like 'wrapup%'
      and extract(hour from entered) >= 9
      and extract(hour from entered) < 17
      and dur_sec is not null
      and dur_sec >= 0
      and dur_sec <= 1800
    group by 1, 2
),
talk as (
    select c.operator_login as login,
           cast(c.wait_start as date) as day,
           sum(c.talk_sec) as talk_sec,
           count(*) as handled
    from v_voice_contacts c
    where c.final_stage = 'operator'
      and c.operator_login is not null
      and c.talk_sec is not null
      and extract(hour from c.wait_start) >= 9
      and extract(hour from c.wait_start) < 17
    group by 1, 2
)
select s.login,
       s.day,
       coalesce(e.department, '') as department,
       coalesce(t.handled, 0) as handled_in_shift,
       round(s.staffed_sec / 3600.0, 2) as staffed_hours,
       round(coalesce(t.talk_sec, 0) / 3600.0, 2) as talk_hours,
       round(coalesce(w.wrap_sec, 0) / 3600.0, 2) as wrap_hours,
       round(100.0 * (coalesce(t.talk_sec, 0) + coalesce(w.wrap_sec, 0))
             / nullif(s.staffed_sec, 0), 1) as occupancy_pct
from shift s
left join wrap w
  on w.login = s.login and w.day = s.day
left join talk t
  on t.login = s.login and t.day = s.day
left join dim_employees e
  on e.login = s.login
order by s.day, occupancy_pct desc, s.login;
