
with src as (
    select
        employee_id,
        project_id,
        date,
        hours,
        row_number() over (partition by employee_id, project_id, date) as dup_rank
    from {{ source('raw', 'timesheets') }}
),
typed as (
    select
        employee_id,
        project_id,
        -- raw date mixes three formats (dd/mm/yyyy, ISO yyyy-mm-dd, dd-Mon-yy);
        -- try_strptime walks the format list and returns NULL if none match
        try_strptime(date, ['%d/%m/%Y', '%Y-%m-%d', '%d-%b-%y'])::date as date,
        try_cast(hours as decimal(5, 2)) as hours,
        dup_rank
    from src
)

select
    -- surrogate PK = md5 of the natural key (employee_id, project_id, date):
    -- one timesheet per employee/project/day; hours is a measure, not part of the grain
    md5(
        coalesce(employee_id, '') || '|' ||
        coalesce(project_id, '')  || '|' ||
        coalesce(date::varchar, '')
    ) as timesheet_id,
    employee_id,
    project_id,
    date,
    hours
from typed
where dup_rank = 1                                      -- one row per natural key (emp, project, day)
  and employee_id is not null                            -- drop missing employee_id
  and date is not null                                    -- drop unparseable date
  and hours is not null                                   -- drop non-numeric hours
  and hours > 0 and hours <= 24                           -- drop out-of-range hours