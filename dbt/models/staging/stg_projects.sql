with ranked as (
    select
        project_id,
        project_name,
        try_cast(budget as decimal(12, 2)) as budget,
        row_number() over (partition by project_id) as dup_rank
    from {{ source('raw', 'projects') }}
)

select
    project_id,
    project_name,
    budget
from ranked
where dup_rank = 1
  and project_id is not null