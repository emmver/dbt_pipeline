-- int_timesheets_validated
-- The cross-source fact-cleaning intermediate: connects stg_timesheets to the
-- clean stg_employees / stg_projects and keeps only rows whose foreign keys
-- resolve to a real dimension row (the accepted fact set). This is the
-- legitimate intermediate role (references multiple atomic staging models).
-- Inner joins (not IN subqueries) enforce referential integrity; because
-- stg_employees / stg_projects hold one row per unique id (dedup survivors),
-- the joins do not fan out. No flags, no status column -- cleaning is a join
-- filter, not a flag.

select
    ts.timesheet_id,
    ts.employee_id,
    ts.project_id,
    ts.date,
    ts.hours
from {{ ref('stg_timesheets') }} ts
inner join {{ ref('stg_employees') }} emp on emp.employee_id = ts.employee_id
inner join {{ ref('stg_projects') }} prj on prj.project_id = ts.project_id