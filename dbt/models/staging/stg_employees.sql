with ranked as (
    select
        employee_id,
        name,
        role,
        row_number() over (partition by employee_id) as dup_rank
    from {{ source('raw', 'employees') }}
)

select
    employee_id,
    name,
    role
from ranked
where dup_rank = 1
  and employee_id is not null