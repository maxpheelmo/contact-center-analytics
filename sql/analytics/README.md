# Примеры аналитических запросов

Запросы читают витрины (`v_interval_volume`, `v_voice_contacts`, `v_text_contacts`, `v_aht_interval`, `v_chat_sessions_interval`, `v_voice_sessions_interval`) и сырые таблицы. Запускать после загрузки sample в Parquet.

| Файл | Что показывает |
|---|---|
| `01_daily_kpis.sql` | Ежедневные KPI по каналам: вход, обработано, потери, Service Level, ASA. CTE и соединение двух зёрен. |
| `02_interval_windows.sql` | Профиль 30-минутных интервалов: LAG/LEAD к соседнему слоту, скользящее среднее, сравнение с тем же интервалом вчера (period-over-period). |
| `03_running_totals_and_peaks.sql` | Накопительный итог нагрузки внутри дня и поиск пиковых интервалов через ROW_NUMBER. |
| `04_channel_funnel.sql` | Воронка по каналам: вход, доля через бота, дошли до очереди, получили ответ. JOIN витрин сессий и нагрузки. |
| `05_aht_and_agent_ranking.sql` | AHT по каналу и рейтинги операторов (ROW_NUMBER, доля от команды через SUM() OVER). |
| `06_occupancy_from_statuses.sql` | Occupancy и Utilization из журнала статусов и разговоров. Оконные функции по смежным статусам. |
| `07_data_quality.sql` | Набор проверок качества: отрицательные длительности, сироты, разрывы связей, выбросы, справочники. |

Вывод прогона на sample лежит в `docs/analytics_queries.md`. Цифры синтетические, это не показатели реальной компании.
