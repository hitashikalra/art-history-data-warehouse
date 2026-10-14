# Art History Data Warehouse

A Snowflake warehouse built on the Met Museum's open-access collection, with dbt models for asking how art changed over time: which media dominated each century, and what each movement's output actually looked like.

## Architecture

```
Met Museum Collection API
        |
        v
ingest/fetch_met_museum.py     Python, rate-limited parallel pulls -> CSV
        |
        v
Snowflake stage -> RAW.ARTWORKS     raw landing table, all text, never edited
        |
        v
dbt
  staging/stg_artworks              typed, cleaned, century + medium family
  seeds/art_movements               movement date windows
  marts/mart_medium_by_century      medium share per century
  marts/mart_movement_trends        count, top medium, top dept per movement
```

## Design choices

- **Raw stays raw.** Everything lands in `RAW.ARTWORKS` as text. All typing and cleanup happens in `stg_artworks`, so I can rebuild every model without re-pulling from the API.
- **Medium grouping.** The Met's `medium` field is free text ("Albumen silver print from glass negative", "Oil on canvas"). The staging model buckets it into about a dozen families so the century comparisons mean something.
- **Movements as a seed.** The API has no movement field, so movements are mapped from object dates using `seeds/art_movements.csv`. It's an approximation and the model says so. Editing the CSV and re-running `dbt seed` changes the mapping.
- **Tests.** Uniqueness and not-null on keys, accepted values on medium families, and a custom test that each century's medium shares add up to 100%.

## Run it

```bash
pip install -r requirements.txt

# 1. Pull the data (about 100k public-domain records; takes a while because of the API rate limit)
python ingest/fetch_met_museum.py --out data/artworks.csv --limit 100000

# 2. Set up Snowflake once, then load
#    export SNOWFLAKE_ACCOUNT=... SNOWFLAKE_USER=... SNOWFLAKE_PASSWORD=...
snowsql -f snowflake/schema.sql
snowsql -f snowflake/load.sql

# 3. Build and test the models
cp dbt/profiles.yml.example ~/.dbt/profiles.yml
cd dbt
dbt seed
dbt build
```

## Example questions

```sql
-- When did photography overtake painting in the collection?
select century, medium_family, share_of_century_pct
from ANALYTICS.MART_MEDIUM_BY_CENTURY
where medium_family in ('Oil paint', 'Photography')
order by century;

-- What did each movement mostly produce?
select * from ANALYTICS.MART_MOVEMENT_TRENDS;
```

## Repo layout

```
ingest/      Met API extractor
snowflake/   warehouse setup and load scripts
dbt/         staging and mart models, movement seed, tests
```
