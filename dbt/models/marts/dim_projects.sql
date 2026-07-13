-- dim_projects
-- Clean project dimension: one row per project_id from stg_projects (the
-- dedup survivors, non-null id). Negative budget is nullified here (the
-- consumer-facing dim). Soft-issue rows (null project_name, null/invalid
-- budget) are retained since the id is valid. Contracted FK target with the
-- PK test. Reads only stg_projects (single atomic source).

select
    project_id,
    project_name,
    case when budget < 0 then null else budget end as budget
from {{ ref('stg_projects') }}