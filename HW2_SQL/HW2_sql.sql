-- ============================================================
-- Домашнее задание к лекции «SQL. Продвинутый»
-- Школа Аналитиков · учебная база hh_school
-- Автор: Иващенко Юлия Васильевна
-- ============================================================

SET search_path TO hh_school;


-- ============================================================
-- БЛОК А. Качество и подготовка данных
-- ============================================================


-- ЗАДАНИЕ А1. Аудит качества данных

-- Сначала проводим исследование, посмотрим что мы вообще имеем

SELECT * FROM calls LIMIT 5;
SELECT * FROM messages LIMIT 5;

-- Теперь приверно понятно что мы имеем, можем приступать к проверкам

-- 1) оценим масштаб

SELECT COUNT(*) FROM calls; -- 251
SELECT COUNT(*) FROM messages; -- 2862

-- 2) можно ли корректно связать событие с откликом

SELECT * FROM responses LIMIT 5;
-- проверям что response_id ведёт к responses, смотрим есть ли там response_id
-- он, есть, значит согласовывать в теории можно

SELECT c.call_id, c.response_id FROM calls c
LEFT JOIN responses r ON c.response_id = r.response_id
WHERE r.response_id IS NULL; -- 8 строк где у звонка нет привязанного отклика, id: 700244–700251
-- значит ломается коммуникация. Теперь проверим для messages

SELECT m.message_id, m.response_id FROM messages m
LEFT JOIN responses r ON m.response_id = r.response_id
WHERE r.response_id IS NULL; -- таких строк нет, у messages связь с откликом в порядке

-- 3) согласуются ли между собой идентификаторы в связанных таблицах
-- даже если response_id существует, поля события могут врать относительно отклика

-- calls
SELECT c.call_id, c.response_id, c.vacancy_id, r.vacancy_id
FROM calls c
JOIN responses r ON  c.response_id = r.response_id
WHERE c.response_id IS NOT NULL
  AND c.vacancy_id IS DISTINCT FROM r.vacancy_id;

-- messages 

SELECT m.message_id, m.response_id, m.vacancy_id, r.vacancy_id
FROM messages m
JOIN responses r ON  m.response_id = r.response_id
WHERE m.response_id IS NOT NULL
  AND m.vacancy_id IS DISTINCT FROM r.vacancy_id;

-- в обеих пусто, значит расхождений по vacancy_id нет ни у звонков, ни у сообщений

-- 4) проверим время
-- calls: событие раньше отклика
SELECT c.call_id, c.call_at, r.created_at
FROM calls c
JOIN responses r ON c.response_id = r.response_id
WHERE c.response_id IS NOT NULL
  AND c.call_at < r.created_at;

-- messages
SELECT m.message_id, m.sent_at, r.created_at
FROM messages m
JOIN responses r ON m.response_id = r.response_id
WHERE m.response_id IS NOT NULL
  AND m.sent_at < r.created_at;

-- оба пустые, значит всё в порядке. Событий раньше отклика нет

-- 5) проверим пропуски, проверим вме столбики

SELECT
  COUNT(*) FILTER 
    (WHERE call_id IS NULL) AS null_call_id,
  COUNT(*) FILTER 
    (WHERE response_id IS NULL) AS null_response_id,
  COUNT(*) FILTER 
    (WHERE call_at IS NULL) AS null_call_at,
  COUNT(*) FILTER 
    (WHERE status IS NULL) AS null_status,
  COUNT(*) filter
    (WHERE call_duration IS NULL) AS null_duration,
  COUNT(*) filter
    (WHERE caller_role IS NULL) AS null_role
FROM calls;
-- у call 8 пропусков в response_id и 70 пропусков в duration. 
-- Cтоит проверить duration это ошибка или просто недозвоны
SELECT status, COUNT(*)
FROM calls
WHERE call_duration IS NULL
GROUP BY status;

SELECT status, COUNT(*), COUNT(call_duration) AS with_duration
FROM calls
GROUP BY status;
-- у всех успешных звонков есть длительность, а пропуски только у неуспешных и одной ошибки.
-- Значит, пустая длительность тут скорее нормальное значение неуспешного/ошибочного звонка, а не поломка

SELECT
  COUNT(*) FILTER  
    (WHERE message_id IS NULL) AS null_message_id,
  COUNT(*) FILTER 
  	(WHERE response_id IS NULL) AS null_response_id,
  COUNT(*) FILTER 
  	(WHERE sent_at IS NULL) AS null_sent_at,
  COUNT(*) FILTER 
  	(WHERE sender_role IS NULL) AS null_role,
  COUNT(*) FILTER 
  	(WHERE message_text IS NULL) AS null_text
FROM messages;
-- хорошо, у message нет пропусков вообще

-- 6) есть ли выбросы или другие странности
-- сначала проверим

-- какие роли бывают
SELECT caller_role, COUNT(*) FROM calls GROUP BY 1;
SELECT sender_role, COUNT(*) FROM messages GROUP BY 1;
-- тут всё хорошо

-- странная длительность у successful
SELECT call_id, call_duration, status
FROM calls
WHERE status = 'successful'
  AND (call_duration <= 0 OR call_duration IS NULL);
-- тути туже всё в порядке

-- теперь, берём только successful с call_duration > 0, считаем среднее, медиану, 99-й перцентиль
-- сколько звонков длиннее p99 и среднее без них —
-- чтобы понять, сильно ли хвост тянет типичную длительность

WITH ok AS (
  SELECT call_id, call_duration
  FROM calls
  WHERE status = 'successful'
    AND call_duration > 0
),
stats AS (
  SELECT
    AVG(call_duration) AS avg_dur,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY call_duration) AS p50,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY call_duration) AS p99
  FROM ok
)
SELECT
  s.avg_dur,
  s.p50,
  s.p99,
  COUNT(*) FILTER (WHERE o.call_duration > s.p99) AS cnt_above_p99,
  AVG(o.call_duration) FILTER (WHERE o.call_duration <= s.p99) AS avg_without_above_p99
FROM ok o
CROSS JOIN stats s
GROUP BY s.avg_dur, s.p50, s.p99;

-- среднее около 467.28, медина 438, p99 ≈ 890, выше p99: 2 звонка, 
-- среднее без них ококло 462 (почти как полное среднее), хвост маленький
-- Значит, 2 длинных звонка — скорее допустимые выбросы, не ошибки.
-- На факт коммуникации не влияют; для "типичной" длительности их можно исключать


-- ============================================================
-- БЛОК Б. История коммуникаций
-- ============================================================


-- ЗАДАНИЕ Б2. Единый слой коммуникаций
-- оставим только коммуникации работодателя. Потом только за поледние 7 дней. 
-- Затем выкинем не звонки без response_id. Обьединим звонки и сообщения, получим как раз 4 числа
-- сколько всего событий, сколько уникальных откликов, звонков, сообщений


WITH calls_prep AS (
  SELECT
    c.response_id,
    c.employer_id,
    c.call_id::text AS event_id,
    c.call_at AS event_at,
    'call' AS event_type
  FROM calls c
  JOIN responses r ON c.response_id = r.response_id
  WHERE c.caller_role = 'employer'
    AND c.response_id IS NOT NULL
    AND c.call_at >= r.created_at
    AND c.call_at <  r.created_at + INTERVAL '7 days'
),
messages_prep AS (
  SELECT
    m.response_id,
    m.employer_id,
    m.message_id::text AS event_id,
    m.sent_at AS event_at,
    'message' AS event_type
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sender_role = 'employer'
    AND m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
events AS (
  SELECT * FROM calls_prep
  UNION ALL
  SELECT * FROM messages_prep
)
SELECT
  COUNT(*) AS total_events,
  COUNT(DISTINCT response_id) AS responses_with_events,
  COUNT(*) FILTER (WHERE event_type = 'call') AS calls_cnt,
  COUNT(*) FILTER (WHERE event_type = 'message') AS messages_cnt
FROM events;

-- получаем:
-- total_events = 1096
-- responses_with_events = 382
-- calls_cnt = 108
-- messages_cnt = 988


-- ЗАДАНИЕ Б3. Таймлайн коммуникаций и витрина отклика
-- шаг 1. Слой уровня события


with
calls_prep AS (
  SELECT
    c.response_id,
    c.employer_id,
    c.call_id::text AS event_id,
    c.call_at AS event_at,
    'call' AS event_type
  FROM calls c
  JOIN responses r ON c.response_id = r.response_id
  WHERE c.caller_role = 'employer'
    AND c.response_id IS NOT NULL
    AND c.call_at >= r.created_at
    AND c.call_at <  r.created_at + INTERVAL '7 days'
),
messages_prep AS (
  SELECT
    m.response_id,
    m.employer_id,
    m.message_id::text AS event_id,
    m.sent_at AS event_at,
    'message' AS event_type
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sender_role = 'employer'
    AND m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
events AS (
  SELECT * FROM calls_prep
  UNION ALL
  SELECT * FROM messages_prep
),
timeline AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS event_no,
    LAG(e.event_at) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS prev_event_at,
    LEAD(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS next_event_type,
    COUNT(*) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS events_so_far,
    FIRST_VALUE(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS first_event_type,
    LAST_VALUE(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_event_type
  FROM events e
)
SELECT * FROM timeline LIMIT 20; 

-- шаг 2. Витрина уровня отклика

WITH calls_prep AS (
  SELECT
    c.response_id,
    c.employer_id,
    c.call_id::text AS event_id,
    c.call_at AS event_at,
    'call' AS event_type
  FROM calls c
  JOIN responses r ON c.response_id = r.response_id
  WHERE c.caller_role = 'employer'
    AND c.response_id IS NOT NULL
    AND c.call_at >= r.created_at
    AND c.call_at <  r.created_at + INTERVAL '7 days'
),
messages_prep AS (
  SELECT
    m.response_id,
    m.employer_id,
    m.message_id::text AS event_id,
    m.sent_at AS event_at,
    'message' AS event_type
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sender_role = 'employer'
    AND m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
events AS (
  SELECT * FROM calls_prep
  UNION ALL
  SELECT * FROM messages_prep
),
timeline AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS event_no,
    LAG(e.event_at) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS prev_event_at,
    LEAD(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS next_event_type,
    COUNT(*) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS events_so_far,
    FIRST_VALUE(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS first_event_type,
    LAST_VALUE(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_event_type
  FROM events e
),
response_mart AS (
  SELECT
    r.response_id,
    v.employer_id,
    v.professional_role,
    r.status,

    COUNT(t.event_id) AS events_cnt,
    COUNT(t.event_id) FILTER (WHERE t.event_type = 'call') AS calls_cnt,
    COUNT(t.event_id) FILTER (WHERE t.event_type = 'message') AS messages_cnt,

    MIN(t.event_at) AS first_event_at,

    MAX(t.event_type) FILTER (WHERE t.event_no = 1) AS first_type,
    MAX(t.event_type) FILTER (WHERE t.event_no = 2) AS second_type,
    MAX(t.last_event_type) AS last_type,

    EXTRACT(EPOCH FROM (MIN(t.event_at) - r.created_at)) / 3600.0 AS hours_to_first,

    MAX(EXTRACT(EPOCH FROM (t.event_at - t.prev_event_at)) / 3600.0) AS max_gap_hours

  FROM responses r
  JOIN vacancies v ON r.vacancy_id = v.vacancy_id
  LEFT JOIN timeline t ON r.response_id = t.response_id
  GROUP BY
    r.response_id,
    v.employer_id,
    v.professional_role,
    r.status,
    r.created_at
)
SELECT
  COUNT(*) AS rows_cnt,
  COUNT(*) FILTER (WHERE events_cnt > 0) AS with_comm,
  COUNT(*) FILTER (WHERE events_cnt = 0) AS without_comm,
  COUNT(*) FILTER (WHERE first_type = 'message') AS first_message,
  COUNT(*) FILTER (WHERE first_type = 'call') AS first_call
FROM response_mart;

-- получаем:
-- rows_cnt = 628
-- with_comm = 382
-- without_comm = 246
-- first_message = 314
-- first_call = 68


-- ЗАДАНИЕ В4. Рейтинг работодателей внутри направления

WITH calls_prep AS (
  SELECT
    c.response_id,
    c.employer_id,
    c.call_id::text AS event_id,
    c.call_at AS event_at,
    'call' AS event_type
  FROM calls c
  JOIN responses r ON c.response_id = r.response_id
  WHERE c.caller_role = 'employer'
    AND c.response_id IS NOT NULL
    AND c.call_at >= r.created_at
    AND c.call_at <  r.created_at + INTERVAL '7 days'
),
messages_prep AS (
  SELECT
    m.response_id,
    m.employer_id,
    m.message_id::text AS event_id,
    m.sent_at AS event_at,
    'message' AS event_type
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sender_role = 'employer'
    AND m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
events AS (
  SELECT * FROM calls_prep
  UNION ALL
  SELECT * FROM messages_prep
),
timeline AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS event_no,
    LAG(e.event_at) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS prev_event_at,
    LEAD(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS next_event_type,
    COUNT(*) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS events_so_far,
    FIRST_VALUE(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS first_event_type,
    LAST_VALUE(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_event_type
  FROM events e
),
response_mart AS (
  SELECT
    r.response_id,
    v.employer_id,
    v.professional_role,
    r.status,
    COUNT(t.event_id) AS events_cnt,
    COUNT(t.event_id) FILTER (WHERE t.event_type = 'call') AS calls_cnt,
    COUNT(t.event_id) FILTER (WHERE t.event_type = 'message') AS messages_cnt,
    MIN(t.event_at) AS first_event_at,
    MAX(t.event_type) FILTER (WHERE t.event_no = 1) AS first_type,
    MAX(t.event_type) FILTER (WHERE t.event_no = 2) AS second_type,
    MAX(t.last_event_type) AS last_type,
    EXTRACT(EPOCH FROM (MIN(t.event_at) - r.created_at)) / 3600.0 AS hours_to_first,
    MAX(EXTRACT(EPOCH FROM (t.event_at - t.prev_event_at)) / 3600.0) AS max_gap_hours
  FROM responses r
  JOIN vacancies v ON r.vacancy_id = v.vacancy_id
  LEFT JOIN timeline t ON r.response_id = t.response_id
  GROUP BY
    r.response_id,
    v.employer_id,
    v.professional_role,
    r.status,
    r.created_at
),
emp_stats AS (
  SELECT
    professional_role,
    employer_id,
    COUNT(*) AS responses_cnt,
    COUNT(*) FILTER (WHERE events_cnt > 0) AS with_comm_cnt,
    100.0 * COUNT(*) FILTER (WHERE events_cnt > 0) / COUNT(*) AS processed_share,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
      ORDER BY CASE WHEN events_cnt > 0 THEN hours_to_first END
    ) AS median_hours,
    PERCENTILE_CONT(0.9) WITHIN GROUP (
      ORDER BY CASE WHEN events_cnt > 0 THEN hours_to_first END
    ) AS p90_hours,
    100.0 * COUNT(*) FILTER (WHERE status = 'invited') / COUNT(*) AS invite_rate
  FROM response_mart
  GROUP BY professional_role, employer_id
  HAVING COUNT(*) >= 8
),
ranked AS (
  SELECT
    *,
    DENSE_RANK() OVER (
      PARTITION BY professional_role
      ORDER BY processed_share DESC, median_hours ASC
    ) AS place
  FROM emp_stats
)
SELECT
  professional_role,
  place,
  employer_id
FROM ranked
WHERE place <= 2
ORDER BY professional_role, place, employer_id;

-- professional_role   |place|employer_id|
-- --------------------+-----+-----------+
-- Аналитик данных     |    1|        109|
-- Аналитик данных     |    2|        103|
-- Дата-инженер        |    1|        106|
-- Дата-инженер        |    2|        101|
-- Продуктовый аналитик|    1|        103|
-- Продуктовый аналитик|    2|        102|
-- Разработчик         |    1|        112|
-- Разработчик         |    2|        104|
-- Тестировщик         |    1|        107|
-- Тестировщик         |    2|        108|


-- ЗАДАНИЕ В5. Скорость ответа работодателя в переписке

WITH msgs AS (
  SELECT
    m.message_id,
    m.response_id,
    m.employer_id,
    m.sender_role,
    m.sent_at,
    LAG(m.sender_role) OVER (
      PARTITION BY m.response_id
      ORDER BY m.sent_at, m.message_id
    ) AS prev_role,
    LAG(m.sent_at) OVER (
      PARTITION BY m.response_id
      ORDER BY m.sent_at, m.message_id
    ) AS prev_sent_at
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
replies AS (
  SELECT
    employer_id,
    EXTRACT(EPOCH FROM (sent_at - prev_sent_at)) / 3600.0 AS reply_hours
  FROM msgs
  WHERE sender_role = 'employer'
    AND prev_role = 'applicant'
)
SELECT
  employer_id,
  COUNT(*) AS replies_cnt,
  AVG(reply_hours) AS avg_hours,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY reply_hours) AS median_hours,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY reply_hours) AS p90_hours
FROM replies
GROUP BY employer_id
ORDER BY median_hours ASC;

-- Общее число ответов: 749

WITH msgs AS (
  SELECT
    m.message_id,
    m.response_id,
    m.employer_id,
    m.sender_role,
    m.sent_at,
    LAG(m.sender_role) OVER (
      PARTITION BY m.response_id
      ORDER BY m.sent_at, m.message_id
    ) AS prev_role,
    LAG(m.sent_at) OVER (
      PARTITION BY m.response_id
      ORDER BY m.sent_at, m.message_id
    ) AS prev_sent_at
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
replies AS (
  SELECT
    employer_id,
    EXTRACT(EPOCH FROM (sent_at - prev_sent_at)) / 3600.0 AS reply_hours
  FROM msgs
  WHERE sender_role = 'employer'
    AND prev_role = 'applicant'
)
SELECT COUNT(*) AS total_replies
FROM replies;

-- медиана: 3.9333333333333336

WITH msgs AS (
  SELECT
    m.message_id,
    m.response_id,
    m.employer_id,
    m.sender_role,
    m.sent_at,
    LAG(m.sender_role) OVER (
      PARTITION BY m.response_id
      ORDER BY m.sent_at, m.message_id
    ) AS prev_role,
    LAG(m.sent_at) OVER (
      PARTITION BY m.response_id
      ORDER BY m.sent_at, m.message_id
    ) AS prev_sent_at
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
replies AS (
  SELECT
    employer_id,
    EXTRACT(EPOCH FROM (sent_at - prev_sent_at)) / 3600.0 AS reply_hours
  FROM msgs
  WHERE sender_role = 'employer'
    AND prev_role = 'applicant'
)
SELECT
  employer_id,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY reply_hours) AS median_hours
FROM replies
GROUP BY employer_id
ORDER BY median_hours ASC
LIMIT 1;

-- ============================================================
-- БЛОК Г.  Сложные типы данных
-- ============================================================

-- ЗАДАНИЕ Г6. Сложные типы данных
-- 6.1


WITH employer_calls AS (
  SELECT c.call_id, c.status, c.call_tags
  FROM calls c
  JOIN responses r ON c.response_id = r.response_id
  WHERE c.caller_role = 'employer'
    AND c.response_id IS NOT NULL
    AND c.call_at >= r.created_at
    AND c.call_at <  r.created_at + INTERVAL '7 days'
),
valid_calls AS (
  SELECT *
  FROM employer_calls
  WHERE (status = 'successful'   AND 'connected'       = ANY(call_tags))
     OR (status = 'unsuccessful' AND 'no_answer'       = ANY(call_tags))
     OR (status = 'error'        AND 'technical_error' = ANY(call_tags))
)
-- counts по бизнес-тегам
SELECT
  COUNT(*) FILTER (WHERE 'screening'  = ANY(call_tags)) AS screening_cnt,
  COUNT(*) FILTER (WHERE 'interview'  = ANY(call_tags)) AS interview_cnt,
  COUNT(*) FILTER (WHERE 'follow_up'  = ANY(call_tags)) AS follow_up_cnt,
  COUNT(*) FILTER (WHERE 'details'    = ANY(call_tags)) AS details_cnt,
  COUNT(*) FILTER (
    WHERE call_tags && ARRAY['screening','interview','follow_up','details']
  ) AS with_any_business_tag,
  AVG(CARDINALITY(call_tags)) AS avg_tags_per_valid_call
FROM valid_calls;


WITH employer_calls AS (
  SELECT c.call_id, c.status, c.call_tags
  FROM calls c
  JOIN responses r ON c.response_id = r.response_id
  WHERE c.caller_role = 'employer'
    AND c.response_id IS NOT NULL
    AND c.call_at >= r.created_at
    AND c.call_at <  r.created_at + INTERVAL '7 days'
),
-- сколько противоречий status vs technical tag
SELECT COUNT(*) AS contradictions
FROM employer_calls ec
WHERE NOT (
     (status = 'successful'   AND 'connected'       = ANY(call_tags))
  OR (status = 'unsuccessful' AND 'no_answer'       = ANY(call_tags))
  OR (status = 'error'        AND 'technical_error' = ANY(call_tags))
);

-- contradictions = 0
-- screening = 25, interview = 31, follow_up = 29, details = 23
-- with_any_business_tag = 108
-- avg_tags_per_valid_call = 4

-- 6.2

WITH emp_msgs AS (
  SELECT
    COALESCE(m.message_meta ->> 'channel', 'unknown') AS channel,
    CASE
      WHEN m.message_meta ? 'is_read'
      THEN (m.message_meta ->> 'is_read')::boolean
    END AS is_read,  -- NULL = признака нет
    COALESCE(jsonb_array_length(m.message_meta -> 'attachments'), 0) AS attachments_cnt
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sender_role = 'employer'
    AND m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
)
SELECT
  channel,
  COUNT(*) AS messages_cnt,
  COUNT(is_read) AS with_read_flag,
  COUNT(*) FILTER (WHERE is_read = false) AS unread_cnt,
  100.0 * COUNT(*) FILTER (WHERE is_read = false)
       / NULLIF(COUNT(is_read), 0) AS unread_share_pct,
  COUNT(*) FILTER (WHERE attachments_cnt > 0) AS with_attachment_cnt,
  100.0 * COUNT(*) FILTER (WHERE attachments_cnt > 0)
       / COUNT(*) AS attachment_share_pct
FROM emp_msgs
GROUP BY channel
ORDER BY channel;

-- web: 628 msg, read_flag 628, unread 52 (8.28%), with_attach 25 (3.98%)
-- mobile_app: 360 msg, read_flag 360, unread 36 (10%), with_attach 14 (3.89%)


-- ============================================================
-- БЛОК Д.  Самостоятельное исследование
-- ============================================================

-- ЗАДАНИЕ Д7.  Что связано с приглашением?

-- Гипотеза 1: у invited выше доля откликов с коммуникацией работодателя за 7 дней.
-- Гипотеза 2: у invited выше среднее число коммуникаций на отклик.
-- Метрики:
--   1) share_with_comm  — факт связи
--   2) avg_events       — интенсивность
--   3) avg_hours_to_first — скорость (другой аспект; новая относительно явных контролей 1–6 как сравнение invited vs other)
--   + responses_cnt в каждой группе


WITH calls_prep AS (
  SELECT
    c.response_id,
    c.employer_id,
    c.call_id::text AS event_id,
    c.call_at AS event_at,
    'call' AS event_type
  FROM calls c
  JOIN responses r ON c.response_id = r.response_id
  WHERE c.caller_role = 'employer'
    AND c.response_id IS NOT NULL
    AND c.call_at >= r.created_at
    AND c.call_at <  r.created_at + INTERVAL '7 days'
),
messages_prep AS (
  SELECT
    m.response_id,
    m.employer_id,
    m.message_id::text AS event_id,
    m.sent_at AS event_at,
    'message' AS event_type
  FROM messages m
  JOIN responses r ON m.response_id = r.response_id
  WHERE m.sender_role = 'employer'
    AND m.sent_at >= r.created_at
    AND m.sent_at <  r.created_at + INTERVAL '7 days'
),
events AS (
  SELECT * FROM calls_prep
  UNION ALL
  SELECT * FROM messages_prep
),
timeline AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS event_no,
    LAG(e.event_at) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS prev_event_at,
    LEAD(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS next_event_type,
    COUNT(*) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS events_so_far,
    FIRST_VALUE(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
    ) AS first_event_type,
    LAST_VALUE(e.event_type) OVER (
      PARTITION BY e.response_id
      ORDER BY e.event_at, e.event_type, e.event_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_event_type
  FROM events e
),
response_mart AS (
  SELECT
    r.response_id,
    v.employer_id,
    v.professional_role,
    r.status,
    COUNT(t.event_id) AS events_cnt,
    COUNT(t.event_id) FILTER (WHERE t.event_type = 'call') AS calls_cnt,
    COUNT(t.event_id) FILTER (WHERE t.event_type = 'message') AS messages_cnt,
    MIN(t.event_at) AS first_event_at,
    MAX(t.event_type) FILTER (WHERE t.event_no = 1) AS first_type,
    MAX(t.event_type) FILTER (WHERE t.event_no = 2) AS second_type,
    MAX(t.last_event_type) AS last_type,
    EXTRACT(EPOCH FROM (MIN(t.event_at) - r.created_at)) / 3600.0 AS hours_to_first,
    MAX(EXTRACT(EPOCH FROM (t.event_at - t.prev_event_at)) / 3600.0) AS max_gap_hours
  FROM responses r
  JOIN vacancies v ON r.vacancy_id = v.vacancy_id
  LEFT JOIN timeline t ON r.response_id = t.response_id
  GROUP BY
    r.response_id,
    v.employer_id,
    v.professional_role,
    r.status,
    r.created_at
)
SELECT
  CASE WHEN status = 'invited' THEN 'invited' ELSE 'other' END AS grp,
  COUNT(*) AS responses_cnt,
  ROUND(100.0 * COUNT(*) FILTER (WHERE events_cnt > 0) / COUNT(*), 2)
    AS share_with_comm_pct,
  ROUND(AVG(events_cnt)::numeric, 3) AS avg_events,
  ROUND(
    AVG(hours_to_first) FILTER (WHERE events_cnt > 0)::numeric
  , 2) AS avg_hours_to_first
FROM response_mart
GROUP BY 1
ORDER BY 1;


-- Гипотеза 1 (выше доля с коммуникацией у invited):
--   invited 58.70% vs other 61.19% → НЕ подтверждается.
--
-- Гипотеза 2 (больше событий у invited):
--   invited 1.630 vs other 1.765 → НЕ подтверждается.
--
-- Дополнительно (по скорости): у invited первая связь даже чуть позже
--   (62.11 vs 59.92 ч). Различия небольшие; это связь, не причинность.
--   n_invited = 92, n_other = 536.


-- То есть по этим данным приглашение не выглядит следствием более активной/быстрой
-- коммуникации работодателя в первые 7 дней — скорее наоборот, чуть слабее, но разрыв маленький.


-- ЗАДАНИЕ Д8. Итог исследования

-- В данных 628 откликов: у 382 (около 61%) была коммуникация работодателя в первые 7 дней,
-- у 246 — не было. Единый слой событий дал 1096 коммуникаций (108 звонков и 988 сообщений).
-- Работодатели чаще начинают с сообщения (314), чем со звонка (68). Скорость ответа в переписке
-- различается: быстрее всех employer 107 (медиана около 3.93 ч; всего измерено 749 ответов).
-- Внутри направлений лидеры по обработке откликов разные (например, Аналитик данных: 109 и 103;
-- Разработчик: 112 и 104). По качеству данных: 8 звонков без response_id нельзя связать с откликом;
-- длительности выше p99 (2 звонка) скорее выбросы, не ошибки факта звонка. Сравнение invited (92)
-- и остальных (536) не показало, что приглашение связано с более частой или более интенсивной
-- коммуникацией за 7 дней: доля с связью 58.7% vs 61.2%, среднее число событий 1.63 vs 1.77.
-- Ограничение: смотрим только коммуникации работодателя в окне 7 дней и не учитываем содержание
-- переписки/качество вакансии.
-- Следующий вопрос: отличается ли конверсия в invite при старте со звонка vs сообщения
--  и при ответе работодателя быстрее медианы?

