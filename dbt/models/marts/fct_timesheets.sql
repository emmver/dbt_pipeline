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