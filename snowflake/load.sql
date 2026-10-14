-- Load the CSV produced by ingest/fetch_met_museum.py into RAW.ARTWORKS.
-- Run from SnowSQL (PUT does not work in the web UI):
--   snowsql -f snowflake/load.sql

USE WAREHOUSE ART_WH;
USE DATABASE ART_HISTORY;
USE SCHEMA RAW;

PUT file://data/artworks.csv @ARTWORKS_STAGE AUTO_COMPRESS = TRUE OVERWRITE = TRUE;

-- Full refresh: the API is the source of truth, so we reload rather than append.
TRUNCATE TABLE ARTWORKS;

COPY INTO ARTWORKS (
  OBJECT_ID, IS_PUBLIC_DOMAIN, TITLE, DEPARTMENT, CLASSIFICATION, OBJECT_NAME,
  MEDIUM, CULTURE, PERIOD, ARTIST_DISPLAY_NAME, ARTIST_NATIONALITY,
  ARTIST_BEGIN_DATE, ARTIST_END_DATE, OBJECT_DATE, OBJECT_BEGIN_DATE,
  OBJECT_END_DATE, COUNTRY, CREDIT_LINE, METADATA_DATE
)
FROM @ARTWORKS_STAGE/artworks.csv.gz
ON_ERROR = 'CONTINUE';

-- Quick check on what landed and what got rejected
SELECT COUNT(*) AS rows_loaded FROM ARTWORKS;
SELECT * FROM TABLE(VALIDATE(ARTWORKS, JOB_ID => '_last')) LIMIT 20;
