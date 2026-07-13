select
    project_id,
    project_name,
    cast(date_trunc('month', date) as date) as month,
    count(*)::integer                    as timesheet_count,
    sum(hours)::decimal(12, 2)           as total_hours,
    count(distinct employee_id)::integer as distinct_employees
from {{ ref('fct_timesheets') }}
group by project_id, project_name, cast(date_trunc('month', date) as date)
order by project_id, month