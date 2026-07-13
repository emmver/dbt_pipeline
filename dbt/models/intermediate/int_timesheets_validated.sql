select
    ts.timesheet_id,
    ts.employee_id,
    ts.project_id,
    ts.date,
    ts.hours
from {{ ref('stg_timesheets') }} ts
inner join {{ ref('stg_employees') }} emp on emp.employee_id = ts.employee_id
inner join {{ ref('stg_projects') }} prj on prj.project_id = ts.project_id