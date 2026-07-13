-- agg_hours_per_project
-- Total hours per project from the clean fact mart. Reads ONLY from
-- fct_timesheets (single source of accepted, enriched facts); no re-joins.
-- project_id uniqueness (the aggregation grain) is asserted here.

select
    project_id,
    project_name,
    count(*)::integer                     as timesheet_count,
    sum(hours)::decimal(12, 2)            as total_hours,
    count(distinct employee_id)::integer  as distinct_employees
from {{ ref('fct_timesheets') }}
group by project_id, project_name
order by total_hours desc