-- How the mix of media changes century by century.
-- share_of_century = this medium's slice of everything dated to that century.

with artworks as (
    select century, medium_family
    from {{ ref('stg_artworks') }}
    where century is not null
),

counts as (
    select
        century,
        medium_family,
        count(*) as artwork_count
    from artworks
    group by 1, 2
)

select
    century,
    medium_family,
    artwork_count,
    round(
        artwork_count / sum(artwork_count) over (partition by century) * 100, 2
    ) as share_of_century_pct,
    rank() over (partition by century order by artwork_count desc) as rank_in_century
from counts
order by century, artwork_count desc
