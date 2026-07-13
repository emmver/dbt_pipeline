-- fct_timesheets
-- The clean timesheets fact mart: the accepted fact set from
-- int_timesheets_validated joined to dim_employees / dim_projects. Pure join,
-- no filters -- int already removed dangling FKs and single-source rejects, so
-- the grain is clean (one row per timesheet_id). PK (timesheet_id) and FK
-- (employee_id -> dim_employees, project_id -> dim_projects) tests run directly
-- on the columns here with no `where` filtering.

select
    ts.timesheet_id,
    ts.employee_id,
    emp.name as employee_name,
    emp.role as employee_role,
    ts.project_id,
    prj.project_name,
    prj.budget as project_budget,
    ts.date,
    ts.hours
from {{ ref('int_timesheets_validated') }} ts
left join {{ ref('dim_employees') }} emp on emp.employee_id = ts.employee_id
left join {{ ref('dim_projects') }}  prj on prj.project_id  = ts.project_id