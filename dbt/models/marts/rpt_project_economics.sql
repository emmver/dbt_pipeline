-- rpt_project_economics
-- Per-project economics: combines the project budget (dim_projects) with logged
-- hours (the per-project rollup) to derive cost-per-hour. LEFT-joins from
-- dim_projects, so it includes ALL projects -- budgeted-but-not-started projects
-- appear with 0 hours, highlighting work that is funded but not yet staffed.
--
-- ASSUMPTION: budget_per_hour = budget / total_hours is meaningful only if
-- `budget` is a labor-cost budget comparable to hours. If `budget` is a total
-- project budget (incl. non-labor costs), treat budget_per_hour as indicative
-- only. budget_per_hour is NULL for projects with no hours or a NULL budget.

select
    p.project_id,
    p.project_name,
    p.budget,
    coalesce(t.total_hours, 0)::decimal(12, 2)       as total_hours,
    coalesce(t.distinct_employees, 0)::integer       as distinct_employees,
    case
        when coalesce(t.total_hours, 0) = 0 then null
        else p.budget / t.total_hours
    end::decimal(18, 4)                              as budget_per_hour
from {{ ref('dim_projects') }} p
left join {{ ref('agg_hours_per_project') }} t on t.project_id = p.project_id
order by p.project_id
