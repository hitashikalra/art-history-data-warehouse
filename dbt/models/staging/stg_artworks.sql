-- One row per artwork, typed and cleaned.
-- Raw text stays untouched in RAW.ARTWORKS; all cleanup lives here.

with source as (
    select * from {{ source('raw', 'artworks') }}
),

typed as (
    select
        try_to_number(object_id)                     as object_id,
        nullif(trim(title), '')                      as title,
        nullif(trim(department), '')                 as department,
        nullif(trim(classification), '')             as classification,
        nullif(trim(medium), '')                     as medium_raw,
        nullif(trim(culture), '')                    as culture,
        nullif(trim(period), '')                     as period,
        nullif(trim(artist_display_name), '')        as artist_name,
        nullif(trim(artist_nationality), '')         as artist_nationality,
        nullif(trim(country), '')                    as country,
        try_to_number(object_begin_date)             as begin_year,
        try_to_number(object_end_date)               as end_year,
        _loaded_at
    from source
    where upper(is_public_domain) = 'TRUE'
),

dated as (
    select
        *,
        -- Midpoint of the date range is a fair single year for objects
        -- dated like "ca. 1850-1860"
        round((begin_year + coalesce(end_year, begin_year)) / 2) as approx_year
    from typed
    where object_id is not null
),

enriched as (
    select
        *,
        -- Centuries: 1850 -> 19, 1900 -> 19, -300 (300 BCE) -> -3
        case
            when approx_year is null then null
            when approx_year > 0 then floor((approx_year - 1) / 100) + 1
            else -(floor((abs(approx_year) - 1) / 100) + 1)
        end                                          as century,

        -- Medium is free text ("Oil on canvas", "Albumen silver print from
        -- glass negative"), so group it into a small set of families
        case
            -- pastel first so "oil pastel" doesn't get counted as oil paint
            when medium_raw ilike '%pastel%'                               then 'Pastel'
            when medium_raw ilike '%oil%'                                  then 'Oil paint'
            when medium_raw ilike '%tempera%'                              then 'Tempera'
            when medium_raw ilike '%watercolor%'
              or medium_raw ilike '%gouache%'                              then 'Watercolor / gouache'
            when medium_raw ilike '%silver%print%'
              or medium_raw ilike '%gelatin%'
              or medium_raw ilike '%albumen%'
              or medium_raw ilike '%photograph%'                           then 'Photography'
            when medium_raw ilike '%etching%'
              or medium_raw ilike '%engraving%'
              or medium_raw ilike '%lithograph%'
              or medium_raw ilike '%woodcut%'                              then 'Printmaking'
            when medium_raw ilike '%graphite%'
              or medium_raw ilike '%charcoal%'
              or medium_raw ilike '%chalk%'
              or medium_raw ilike '%ink%'                                  then 'Drawing'
            when medium_raw ilike '%bronze%'
              or medium_raw ilike '%marble%'
              or medium_raw ilike '%stone%'                                then 'Sculpture'
            when medium_raw ilike '%ceramic%'
              or medium_raw ilike '%porcelain%'
              or medium_raw ilike '%earthenware%'
              or medium_raw ilike '%stoneware%'                            then 'Ceramics'
            when medium_raw ilike '%silk%'
              or medium_raw ilike '%cotton%'
              or medium_raw ilike '%wool%'
              or medium_raw ilike '%linen%'                                then 'Textile'
            when medium_raw is null                                        then 'Unknown'
            else 'Other'
        end                                          as medium_family
    from dated
)

select * from enriched
