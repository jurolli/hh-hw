-- ============================================================
-- Домашнее задание к лекции «SQL. Введение»
-- Школа Аналитиков · учебная база hh_school
-- Автор: Иващенко Юлия Васильевна
-- ============================================================

SET search_path TO hh_school;

-- ============================================================
-- БЛОК А. Разминка: термины и структура (текстом)
-- ============================================================

-- ЗАДАНИЕ А1
-- 1. Категория и конкретный тип колонок:
--    vacancies.salary_from        — категория: числовой       тип: INT
--    vacancies.vacancy_name       — категория: строковый      тип: в схеме TEXT
--    vacancies.published_at       — категория: дата и время   тип: TIMESTAMP
--    employers.is_accredited_it   — категория: логический     тип: BOOLEAN
--    responses.created_at         — категория: дата и время   тип: TIMESTAMP
--
-- 2. Первичные ключи таблиц:
--    areas: area_id
--    employers: employer_id
--    vacancies: vacancy_id
--    vacancy_details: vacancy_id (чем особенный: первичный ключ vacancy_details
--                                 это одновременно и внешний ключ на vacancies,
--                                 поэтому связь 1:1, и своего отдельного id у таблицы нет)
--    responses: response_id
--
-- 3. Почему vacancy_name не может быть первичным ключом:
--    Первичный ключ должен быть уникальным, а vacancy_name повторяется:
--    самое частое название «Стажёр: аналитик данных» встречается 6 раз.

SELECT vacancy_name, count(*) AS cnt
FROM vacancies
GROUP BY vacancy_name
ORDER BY cnt DESC
LIMIT 1;

-- Вывод:
-- vacancy_name            | cnt
-- Стажёр: аналитик данных | 6
-- Значит, vacancy_name не годится как PK: одно имя указывает сразу на несколько вакансий.


-- 4. Что произойдёт при записи строки «по договорённости» в salary_from:
--    СУБД вернёт ошибку типа: нельзя записать текст в INTEGER.
--    Это хорошо, типы ловят мусор на входе, и аналитик может спокойно считать суммы,
--    средние и сравнения, не разбирая «грязные» строки


-- ============================================================
-- БЛОК Б. Первые запросы: SELECT, WHERE, ORDER BY
-- ============================================================

-- ЗАДАНИЕ Б1
-- Запрос: experience
SELECT DISTINCT experience
FROM vacancies
ORDER BY 1;

-- Запрос: employment
SELECT DISTINCT employment
FROM vacancies
ORDER BY 1;

-- Запрос: professional_role
SELECT DISTINCT professional_role
FROM vacancies
ORDER BY 1;

-- Вывод: в experience 3 значения, в employment 3, в professional_role 5
-- Проблем с качеством не видно: одно и то же не записано по-разному, NULL нет
-- Заметно только, что в experience нет уровня «Более 6 лет» — ограничение учебной базы


-- ЗАДАНИЕ Б2
-- Запрос 1: стажировки в Москве без опыта, вакансия открыта
SELECT vacancy_id, vacancy_name, salary_from, published_at
FROM vacancies
WHERE employment = 'Стажировка'
  AND experience = 'Нет опыта'
  AND area_id = 1
  AND closed_at IS NULL
ORDER BY published_at DESC;

-- для сравнения: без фильтра по Москве
SELECT vacancy_id, vacancy_name, salary_from, published_at
FROM vacancies
WHERE employment = 'Стажировка'
  AND experience = 'Нет опыта'
  AND closed_at IS NULL
ORDER BY published_at DESC;

-- Запрос 2: топ-10 вакансий по salary_from
SELECT vacancy_name, professional_role, salary_from
FROM vacancies
WHERE salary_from IS NOT NULL
ORDER BY salary_from DESC
LIMIT 10;

-- Вывод: первый запрос нашёл 8 вакансий; без условия про Москву их становится 10
-- (добавляются vacancy_id 1029 и 1022). Для соискателя это значит, что узкий фильтр
-- по городу отсекает часть подходящих стажировок. Во втором запросе лидируют
-- Senior-позиции разработчика и дата-инженера с нижней границей 190–195 тыс


-- ЗАДАНИЕ Б3
-- Ловушка 1. NULL — выполнить и объяснить результат
SELECT count(*) FROM vacancies WHERE closed_at = NULL;
SELECT count(*) FROM vacancies WHERE closed_at IS NULL;

-- Ловушка 2. AND / OR — выполнить и объяснить результат
SELECT count(*) FROM vacancies
WHERE area_id = 1 OR area_id = 2 AND experience = 'Нет опыта';

SELECT count(*) FROM vacancies
WHERE (area_id = 1 OR area_id = 2) AND experience = 'Нет опыта';

-- Вывод:
-- Ловушка 1: первый запрос вернул 0, второй — 33. Ошибки не было, потому что сравнение с NULL не даёт TRUE.
-- Это опаснее падения, потому легко принять 0 за то, открытых вакансий нет. По смыслуclosed_at IS NULL
--  значит, что вакансия ещё открыта.

-- Ловушка 2: AND сильнее OR, поэтому первый запрос читается как
-- area_id = 1 OR (area_id = 2 AND experience = 'Нет опыта') и даёт 31( Москва или Питер без опыта). 
-- На вопрос «Москва или Петербург, но обязательно без опыта» отвечает второй
-- запрос с скобками — он даёт 20.


-- ============================================================
-- БЛОК В. Агрегации и метрики
-- ============================================================

-- ЗАДАНИЕ В1
-- Запрос 1: счётчики (строки, зарплата указана, направления, работодатели)
SELECT
    count(*) AS total_rows,
    count(salary_from) AS with_salary_from,
    count(DISTINCT professional_role) AS roles,
    count(DISTINCT employer_id) AS employers
FROM vacancies;

-- Запрос 2: доля активных вакансий 
SELECT
    count(CASE WHEN closed_at IS NULL THEN 1 END) AS open_vacancies,
    count(CASE WHEN closed_at IS NOT NULL THEN 1 END) AS closed_vacancies,
    round(
        100.0 * count(CASE WHEN closed_at IS NULL THEN 1 END) / count(*),
        1
    ) AS open_pct
FROM vacancies;

-- Вывод: count(*) = 52 это все строки; count(salary_from) = 44 это только непустые строки salary_from зарплаты;
-- count(DISTINCT ...) даёт 5 направлений и 12 работодателей без дублей
-- Руководителю: сейчас открыто 33 вакансии из 52, то есть 63,5% активны


-- ЗАДАНИЕ В2
-- Запрос 1: направления — вакансии, работодатели, средняя зарплата
SELECT
    professional_role,
    count(*) AS vacancies,
    count(DISTINCT employer_id) AS employers,
    round(avg(salary_from)) AS avg_salary_from
FROM vacancies
GROUP BY professional_role
ORDER BY vacancies DESC;

-- Запрос 2: только направления с ≥ 5 открытыми вакансиями (WHERE + HAVING)
SELECT
    professional_role,
    count(*) AS vacancies,
    count(DISTINCT employer_id) AS employers,
    round(avg(salary_from)) AS avg_salary_from
FROM vacancies
WHERE closed_at IS NULL
GROUP BY professional_role
HAVING count(*) >= 5
ORDER BY vacancies DESC;

-- Вывод: «Аналитик данных» (16) и «Разработчик» (15) вместе дают 31 из 52, этобольше половины рынка. 
-- Соискатель мог бы решить «иди в аналитику или разработку», но без зарплат по городам,
-- конкуренции откликов и закрываемости такой вывод не очень
--
-- «Только открытые» — в WHERE, потому что это фильтр строк до группировки;
-- «не менее пяти» — в HAVING, потому что это условие на результат агрегата.
-- WHERE count(*) >= 5 СУБД не примет: агрегаты в WHERE использовать нельзя.
--
-- avg(salary_from) отвечает на вопрос «какова средняя нижняя граница среди вакансий, где salary_from заполнен»;
-- не отвечает, сколько реально платят
-- (нет salary_to / офферов) и что с вакансиями без указанной зарплаты


-- ============================================================
-- БЛОК Г. Соединение таблиц
-- ============================================================

-- ЗАДАНИЕ Г1
-- Запрос: топ-5 по salary_from с названием компании и городом (псевдонимы таблиц)
SELECT
    v.vacancy_name,
    e.employer_name,
    a.area_name,
    v.salary_from
FROM vacancies AS v
JOIN employers AS e ON v.employer_id = e.employer_id
JOIN areas AS a ON v.area_id = a.area_id
WHERE v.salary_from IS NOT NULL
ORDER BY v.salary_from DESC
LIMIT 5;

-- Вывод: топ возглавляют Senior разработчик в «Северный Код» (СПб, 195000) и Senior дата-инженер в 
-- «УралСофт» (Екатеринбург, 190000). Если убрать псевдонимы и написать просто area_id,
--  СУБД не поймёт, из какой таблицы колонка: она есть и в vacancies, и в areas — будет ошибка


-- ЗАДАНИЕ Г2
-- Запрос 1: все работодатели, число вакансий и откликов (LEFT JOIN)
SELECT
    e.employer_name,
    count(DISTINCT v.vacancy_id) AS vacancies,
    count(r.response_id) AS responses
FROM employers AS e
LEFT JOIN vacancies AS v ON e.employer_id = v.employer_id
LEFT JOIN responses AS r ON v.vacancy_id = r.vacancy_id
GROUP BY e.employer_id, e.employer_name
ORDER BY responses DESC;

-- Запрос 2: тот же запрос с INNER JOIN
SELECT
    e.employer_name,
    count(DISTINCT v.vacancy_id) AS vacancies,
    count(r.response_id) AS responses
FROM employers AS e
INNER JOIN vacancies AS v ON e.employer_id = v.employer_id
INNER JOIN responses AS r ON v.vacancy_id = r.vacancy_id
GROUP BY e.employer_id, e.employer_name
ORDER BY responses DESC;

-- Вывод: вакансии считаем через count(DISTINCT ...), потому что JOIN с responses размножает строки: 
-- одна вакансия с 10 откликами дала бы count(*) = 10.
-- Во втором запросе пропала «ГринЭнерго»: у неё есть вакансия, но 0 откликов, а INNER JOIN к responses 
-- отбрасывает такие строки — для HR это как раз компании, которых стоит спросить «почему нет интереса».

-- Правило: нужен полный список слева, включая нули — LEFT JOIN; нужны только
-- пересечения с фактом связи — INNER JOIN


-- ============================================================
-- БЛОК Д. Функции и финальный кейс
-- ============================================================

-- ЗАДАНИЕ Д1
-- Запрос: помесячная динамика откликов и конверсия
-- (месяц как дата, условный агрегат, nullif в знаменателе)
SELECT
    date_trunc('month', created_at)::date AS month,
    count(*) AS responses,
    count(*) FILTER (WHERE status = 'invited') AS invitations,
    round(
        100.0 * count(*) FILTER (WHERE status = 'invited')
        / nullif(count(*), 0),
        1
    ) AS conversion_pct
FROM responses
GROUP BY date_trunc('month', created_at)
ORDER BY month;

-- Вывод: максимальная конверсия — в июне 2026: 19,5% (23 приглашения из 118)
-- Этому месяцу можно доверять: объём большой, не «4 из 24». Последний месяц
--  лучше не брать в выводы, всего 41 отклик и просадка до 7,3% —
-- похоже на неполный период, а не на реальное ухудшение рынка


-- ЗАДАНИЕ Д2
-- Запрос: таблица по направлениям (вакансии, отклики, приглашения,
-- откликов на вакансию, конверсия)
SELECT
    v.professional_role,
    count(DISTINCT v.vacancy_id) AS vacancies,
    count(r.response_id) AS responses,
    count(r.response_id) FILTER (WHERE r.status = 'invited') AS invitations,
    round(
        count(r.response_id) * 1.0 / nullif(count(DISTINCT v.vacancy_id), 0),
        2
    ) AS responses_per_vacancy,
    round(
        100.0 * count(r.response_id) FILTER (WHERE r.status = 'invited')
        / nullif(count(r.response_id), 0),
        1
    ) AS conversion_pct
FROM vacancies AS v
LEFT JOIN responses AS r ON v.vacancy_id = r.vacancy_id
GROUP BY v.professional_role
ORDER BY vacancies DESC;

-- Письменные ответы:
--  1. Совпадает ли направление с наибольшим числом вакансий с направлением
--    с наибольшей конверсией?
--      Нет. Больше всего вакансий у «Аналитик данных» (16), а максимальная
--      конверсия — у «Тестировщик» (35,9%)
-- 2. Какое направление выбрать и почему (опираясь на два столбца):
--    Для отклика выбрала бы «Тестировщик»: конверсия в приглашение высокая
--    (35,9%), а конкуренция умеренная (около 5,6 откликов на вакансию) —
--    в отличие от аналитики данных, где откликов на вакансию почти 20
-- 3. Оговорка к выводу:
--    Оговорка: таблица не говорит о зарплате, городе и качестве приглашений —
--    высокая конверсия может быть и в слабые/низкооплачиваемые позиции


-- ============================================================
-- БЛОК Е. Со звёздочкой
-- ============================================================

-- ЗАДАНИЕ Е1
-- Исходный запрос (выполнить и посмотреть результат):
SELECT v.professional_role,
    count(*) AS vacancies,
    sum(v.salary_from) AS total_salary,
    count(r.response_id) / count(*) AS responses_per_vacancy
FROM vacancies v
JOIN responses r ON v.vacancy_id = r.vacancy_id
WHERE v.closed_at = NULL
GROUP BY 1;

-- Ошибки (минимум четыре):
-- 1. WHERE closed_at = NULL — сравнение с NULL всегда UNKNOWN, запрос
--    возвращает 0 строк (это та ошибка, которая «обнуляет» результат)
-- 2. INNER JOIN отбрасывает открытые вакансии без откликов
-- 3. После JOIN count(*) считает строки связки (отклики), а не вакансии
-- 4. sum(v.salary_from) завышен: зарплата одной вакансии суммируется
--    столько раз, сколько у неё откликов
-- 5. count(r.response_id) / count(*) — целочисленное деление; метрика
--    «откликов на вакансию» всё равно считается неправильно из-за зерна JOIN

-- Исправленный запрос:
SELECT
    v.professional_role,
    count(DISTINCT v.vacancy_id) AS vacancies,
    round(avg(v.salary_from)) AS avg_salary_from,
    round(
        count(r.response_id) * 1.0
        / nullif(count(DISTINCT v.vacancy_id), 0),
        2
    ) AS responses_per_vacancy
FROM vacancies AS v
LEFT JOIN responses AS r ON v.vacancy_id = r.vacancy_id
WHERE v.closed_at IS NULL
GROUP BY v.professional_role
ORDER BY vacancies DESC;

-- Какие два правила из лекции защитили бы от этих ошибок при написании:
-- 1. NULL сравниваем только через IS NULL / IS NOT NULL, никогда через =
-- 2. После JOIN проверяем зерно строки: для «числа вакансий» пишем
--    count(DISTINCT ...), а чтобы деление не было целочисленным —
--    умножаем числитель на 1.0 и защищаем знаменатель через nullif
