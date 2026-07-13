-- agg_hours_per_project_monthly
-- Monthly hours per project (project x month). Adds the TIME dimension to the
-- per-project rollup, revealing each project's burn-down / tempo over time --
-- a flat annual total hides this. Derives the month from the fact date directly
-- (no dim_date needed). One row per (project_id, month). Reads only fct_timesheets.

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