-- int_timesheets_validated
-- The cross-source fact-cleaning intermediate: connects stg_timesheets to the
-- clean stg_employees / stg_projects and filters dangling FKs -> the accepted
-- fact set. This is the legitimate intermediate role (joins/references multiple
-- atomic staging models). Uses semi-joins (IN) against the clean dim-source
-- keys to avoid fan-out. No flags, no status column -- cleaning is a where
-- filter, not a flag.

select
    ts.timesheet_id,
    ts.employee_id,
    ts.project_id,
    ts.date,
    ts.hours
from {{ ref('stg_timesheets') }} ts
where ts.employee_id in (select employee_id from {{ ref('stg_employees') }} where employee_id is not null)
  and ts.project_id  in (select project_id  from {{ ref('stg_projects') }}  where project_id is not null)