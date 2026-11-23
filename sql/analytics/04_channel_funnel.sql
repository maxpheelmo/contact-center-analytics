-- 04_channel_funnel.sql
-- Воронка обращений по каналам: вход, бот/робот, очередь, ответ оператора, потери.
--
-- Задача: понять, где «худеет» поток, и связать сессионные витрины с витриной нагрузки.
-- Зерно: день × канал.
--
-- JOIN:
--   * голос: v_voice_sessions_interval  (сессии: вход IVR, робот, прямые в очередь)
--            + v_interval_volume        (попадания в рабочую очередь, ответы, потери)
--   * чат:   v_chat_sessions_interval   (сессии, доля через бота, дошли, отвечены)
--            + v_interval_volume
--   * почта: только v_interval_volume   (письмо сразу в очереди, отдельного входа нет)
--
-- В публичном sample голосовые сессии начинаются сразу в рабочей очереди,
-- поэтому entry_sessions = 0, а весь объём попадает в direct_queue.
-- Так и должно быть: в выгрузку не входили строки входного IVR.
-- На чате воронка полнее: часть сессий идёт через проект чат-бота.

with voice_sess as (
    select day,
           sum(entry_sessions)                          as entry_sessions,
           sum(entry_reached_queue)                     as entry_reached_queue,
           sum(entry_via_robot)                         as entry_via_robot,
           sum(direct_queue)                            as direct_queue,
           sum(entry_reached_queue) + sum(direct_queue) as sessions_in_queue
    from v_voice_sessions_interval
    group by day
),
chat_sess as (
    select day,
           sum(sessions)          as sessions,
           sum(sessions_via_bot)  as sessions_via_bot,
           sum(reached_queue)     as reached_queue,
           sum(answered_queue)    as answered_queue,
           sum(no_operator)       as no_operator,
           sum(bot_no_operator)   as bot_no_operator
    from v_chat_sessions_interval
    group by day
),
vol as (
    select day,
           channel,
           sum(entries)   as entries,
           sum(offered)   as offered,
           sum(handled)   as handled,
           sum(abandoned) as abandoned
    from v_interval_volume
    group by day, channel
)
select v.day,
       v.channel,
       case
           when v.channel = 'Голос' then s.entry_sessions
           when v.channel = 'Чат'   then c.sessions
           else v.offered
       end as step_entry,
       case
           when v.channel = 'Голос' then s.entry_via_robot
           when v.channel = 'Чат'   then c.sessions_via_bot
           else 0
       end as step_via_bot_or_robot,
       case
           when v.channel = 'Голос' then s.sessions_in_queue
           when v.channel = 'Чат'   then c.reached_queue
           else v.entries
       end as step_reached_queue,
       v.handled as step_answered,
       v.abandoned as step_lost,
       case
           when v.channel = 'Голос' then s.direct_queue
           else 0
       end as voice_direct_queue,
       round(
           100.0 * v.handled / nullif(
               case
                   when v.channel = 'Голос' then s.sessions_in_queue
                   when v.channel = 'Чат'   then c.reached_queue
                   else v.entries
               end, 0
           ), 1
       ) as answer_rate_pct
from vol v
left join voice_sess s
  on s.day = v.day
 and v.channel = 'Голос'
left join chat_sess c
  on c.day = v.day
 and v.channel = 'Чат'
order by v.day, v.channel;
