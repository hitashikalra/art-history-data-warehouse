-- Western art movements mapped by date range (see seeds/art_movements.csv),
-- with the dominant medium and department for each.
-- This is a date-based approximation: an 1875 Japanese woodblock print lands
-- in the "Impressionism" window. Filter on artist_nationality or department
-- to narrow it to European painting if that's the question.

with artworks as (
    select * from {{ ref('stg_artworks') }}
    where approx_year is not null
),

movements as (
    select * from {{ ref('art_movements') }}
),

joined as (
    select
        m.movement,
        m.start_year,
        a.medium_family,
        a.department,
        a.object_id
    from artworks a
    join movements m
      on a.approx_year between m.start_year and m.end_year
),

medium_rank as (
    select
        movement,
        medium_family,
        count(*) as n,
        row_number() over (partition by movement order by count(*) desc) as rn
    from joined
    group by 1, 2
),

department_rank as (
    select
        movement,
        department,
        count(*) as n,
        row_number() over (partition by movement order by count(*) desc) as rn
    from joined
    group by 1, 2
)

select
    j.movement,
    min(j.start_year)                       as start_year,
    count(distinct j.object_id)             as artwork_count,
    max(case when mr.rn = 1 then mr.medium_family end) as top_medium,
    max(case when dr.rn = 1 then dr.department end)    as top_department
from joined j
left join medium_rank mr     on j.movement = mr.movement and mr.rn = 1
left join department_rank dr on j.movement = dr.movement and dr.rn = 1
group by j.movement
order by start_year
