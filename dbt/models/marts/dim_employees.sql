select
    employee_id,
    name,
    role
from {{ ref('stg_employees') }}