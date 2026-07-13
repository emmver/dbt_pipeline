select
    project_id,
    project_name,
    case when budget < 0 then null else budget end as budget
from {{ ref('stg_projects') }}