-- dim_employees
-- Clean employee dimension: one row per employee_id from stg_employees (the
-- dedup survivors, non-null id). Soft-issue rows (null name/role) are retained
-- since the id is valid. Contracted FK target with the PK test. Reads only
-- stg_employees (single atomic source).

select
    employee_id,
    name,
    role
from {{ ref('stg_employees') }}