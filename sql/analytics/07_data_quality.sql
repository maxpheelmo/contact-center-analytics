-- 07_data_quality.sql
-- Проверки качества данных. Один набор строк: check_name, severity, n, note.
--
-- Намеренно не используем current_date: рабочие витрины v_queue_check и v_entry_check
-- отсекают 30 дней от сегодня, и на историческом sample они были бы пустыми.
-- Здесь окно берётся из самих данных (все строки sample).
--
-- На синтетике большинство проверок должно дать n = 0. Это нормально:
-- sample собирался аккуратно. Запрос нужен как каркас, который я гонял на боевых данных.

with voice_issues as (
    select 'voice_negative_wait' as check_name, 'error' as severity,
           count(*) as n,
           'Ожидание в очереди меньше нуля' as note
    from v_voice_contacts
    where wait_sec < 0
    union all
    select 'voice_negative_talk', 'error',
           count(*),
           'Длительность разговора меньше нуля'
    from v_voice_contacts
    where talk_sec is not null and talk_sec < 0
    union all
    select 'voice_answered_without_leg', 'error',
           count(*),
           'Принят оператором, но нет плеча разговора (next_leg_id / join на voice_call_legs)'
    from v_voice_contacts
    where final_stage = 'operator' and (operator_login is null or talk_end_time is null)
    union all
    select 'voice_ended_before_connected', 'error',
           count(*),
           'Плечо разговора: ended раньше connected'
    from voice_call_legs
    where connected is not null and ended is not null and ended < connected
    union all
    select 'voice_unknown_project', 'warn',
           count(*),
           'project_id из очереди нет в dim_projects'
    from voice_queued_calls q
    left join dim_projects p on p.uuid = q.project_id
    where p.uuid is null
    union all
    select 'voice_talk_outlier_4h', 'warn',
           count(*),
           'Разговор длиннее 4 часов (такие строки отбрасывает витрина AHT)'
    from v_voice_contacts
    where talk_sec > 4 * 3600
),
text_issues as (
    select 'text_negative_wait', 'error',
           count(*),
           'Ожидание ответа оператора меньше нуля'
    from v_text_contacts
    where wait_answer_sec is not null and wait_answer_sec < 0
    union all
    select 'text_finish_before_start', 'error',
           count(*),
           'Итерация закрыта раньше, чем началась'
    from chat_session_iterations
    where finish_time is not null and start_time is not null and finish_time < start_time
    union all
    select 'text_answered_without_operator', 'error',
           count(*),
           'Есть first_oper_answer_time, но oper_id пустой'
    from chat_session_iterations
    where first_oper_answer_time is not null and (oper_id is null or oper_id = '')
    union all
    select 'text_unknown_project', 'warn',
           count(*),
           'project_id итерации нет в dim_projects'
    from chat_session_iterations i
    left join dim_projects p on p.uuid = i.project_id
    where p.uuid is null
),
status_issues as (
    select 'status_leaved_before_entered', 'error',
           count(*),
           'Статус закончился раньше, чем начался'
    from agent_status_changes
    where leaved is not null and entered is not null and leaved < entered
    union all
    select 'status_unknown_agent', 'warn',
           count(*),
           'Логин из журнала статусов не найден в dim_employees'
    from agent_status_changes s
    left join dim_employees e on e.login = s.login
    where e.login is null
    union all
    select 'voice_wrap_missing_when_statuses_exist', 'warn',
           count(*),
           'Принятый звонок в день, где есть статусы, но wrap-up не привязался'
    from v_aht_interval
    where channel = 'Голос' and wrap_covered = 1 and handled > 0 and wrap_found = 0
),
info as (
    select 'info_voice_rows', 'info',
           count(*),
           'Строк в voice_queued_calls (для масштаба)'
    from voice_queued_calls
    union all
    select 'info_chat_iterations', 'info',
           count(*),
           'Строк в chat_session_iterations'
    from chat_session_iterations
    union all
    select 'info_agent_status_rows', 'info',
           count(*),
           'Строк в agent_status_changes'
    from agent_status_changes
    union all
    select 'info_duplicate_voice_queue_id', 'error',
           count(*) - count(distinct id),
           'Повторяющиеся id в voice_queued_calls'
    from voice_queued_calls
    union all
    select 'info_duplicate_iteration_id', 'error',
           count(*) - count(distinct id),
           'Повторяющиеся id в chat_session_iterations (после выбора последней версии)'
    from chat_session_iterations
)
select check_name, severity, n, note from voice_issues
union all
select * from text_issues
union all
select * from status_issues
union all
select * from info
order by case severity when 'error' then 1 when 'warn' then 2 else 3 end,
         check_name;
