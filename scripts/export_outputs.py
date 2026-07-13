"""Export the mart tables to warehouse/outputs/*.csv (Task 3 deliverables).

Reproducible: re-run after `dbt run` to refresh the cleaned/output datasets.
Exports the four consumer-facing mart tables from main_marts in a stable
column order, overwriting the CSVs in place.
"""
import duckdb

con = duckdb.connect("warehouse/dbt_pipeline.duckdb", read_only=True)

# (table, output filename, ordered column list)
exports = [
    (
        "fct_timesheets",
        "fct_timesheets.csv",
        "timesheet_id, employee_id, employee_name, employee_role, "
        "project_id, project_name, project_budget, date, hours",
    ),
    (
        "agg_hours_per_project",
        "agg_hours_per_project.csv",
        "project_id, project_name, timesheet_count, total_hours, distinct_employees",
    ),
    (
        "agg_hours_per_project_monthly",
        "agg_hours_per_project_monthly.csv",
        "project_id, project_name, month, timesheet_count, total_hours, "
        "distinct_employees",
    ),
    (
        "rpt_project_economics",
        "rpt_project_economics.csv",
        "project_id, project_name, budget, total_hours, distinct_employees, "
        "budget_per_hour",
    ),
]

for table, fname, cols in exports:
    path = f"warehouse/outputs/{fname}"
    con.execute(
        f'copy (select {cols} from main_marts."{table}") '
        f"to '{path}' (header, delimiter ',')"
    )
    n = con.execute(f'select count(*) from main_marts."{table}"').fetchone()[0]
    print(f"  wrote {fname} ({n} rows)")

print("done.")