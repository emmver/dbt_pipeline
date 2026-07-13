
with src as (
    select
        employee_id,
        project_id,
        date,
        hours,
        row_number() over (partition by employee_id, project_id, date, hours) as dup_rank
    from {{ source('raw', 'timesheets') }}
),
typed as (
    select
        employee_id,
        project_id,
        coalesce(
            try_cast(date as date),
            try_strptime(date, '%d/%m/%Y')::date,
            try_strptime(date, '%d-%b-%y')::date
        ) as date,
        try_cast(hours as decimal(5, 2)) as hours,
        dup_rank
    from src
)

select
    md5(
        coalesce(employee_id, '') || '|' ||
        coalesce(project_id, '')  || '|' ||
        coalesce(date::varchar, '') || '|' ||
        coalesce(hours::varchar, '')
    ) as timesheet_id,
    employee_id,
    project_id,
    date,
    hours
from typed
where dup_rank = 1                                      -- drop exact duplicates
  and employee_id is not null                            -- drop missing employee_id
  and date is not null                                    -- drop unparseable date
  and hours is not null                                   -- drop non-numeric hours
  and hours > 0 and hours <= 24                           -- drop out-of-range hours