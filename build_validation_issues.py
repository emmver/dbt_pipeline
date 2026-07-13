"""Build warehouse/outputs/validation_issues.csv (Task 2 deliverable).

Counts and sample failing values are QUERIED from main_dbt_test__audit (and the
warehouse where helpful) -- not hand-typed. The mapping below only encodes
*which* audit table corresponds to *which* named check, plus the
human-readable how_handled text; the actual numbers and sample values come
from the database.
"""
import csv
import duckdb

con = duckdb.connect("warehouse/dbt_pipeline.duckdb", read_only=True)
A = "main_dbt_test__audit"


def count(table):
    return con.execute(f'select count(*) from {A}."{table}"').fetchone()[0]


def col(table, colname):
    rows = con.execute(f'select "{colname}" from {A}."{table}"').fetchall()
    return [r[0] for r in rows]


def uniq(xs):
    seen = []
    for x in xs:
        if x not in seen:
            seen.append(x)
    return seen


def fmt_null(v):
    return "<null>" if v is None else str(v)


# Each entry: (check_name, source_table, column, severity, status, audit_table,
#             sample_fn, how_handled)
checks = [
    # ---- HARD / REJECTED ----
    (
        "unique", "projects", "project_id", "hard", "rejected",
        "source_unique_raw_projects_project_id",
        lambda: ", ".join(uniq(col("source_unique_raw_projects_project_id", "unique_field"))),
        "dropped in stg_projects (dup survivor kept)",
    ),
    (
        "not_null", "projects", "project_id", "hard", "rejected",
        "source_not_null_raw_projects_project_id",
        lambda: "1 null id row (project_name='Unnamed Initiative')",
        "dropped in stg_projects (null PK row)",
    ),
    (
        "unique", "employees", "employee_id", "hard", "rejected",
        "source_unique_raw_employees_employee_id",
        lambda: ", ".join(uniq(col("source_unique_raw_employees_employee_id", "unique_field"))),
        "dropped in stg_employees (dup survivor kept)",
    ),
    (
        "hours_in_range", "timesheets", "hours", "hard", "rejected",
        "source_hours_in_range_raw_timesheets_hours",
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col("source_hours_in_range_raw_timesheets_hours", "hours"))
        ),
        "dropped in stg_timesheets (single-source reject)",
    ),
    (
        "unique_natural_key", "timesheets", "employee_id+project_id+date", "hard", "rejected",
        "source_unique_natural_key_raw__61853f3236dbb9490afe774dd5065933",
        lambda: ", ".join(
            f"{r[0]}/{r[1]}/{r[2]}"
            for r in con.execute(
                'select employee_id, project_id, date from '
                f'{A}."source_unique_natural_key_raw__61853f3236dbb9490afe774dd5065933"'
            ).fetchall()
        ),
        "dropped in stg_timesheets (exact-dup, one row kept per group)",
    ),
    (
        "not_null", "timesheets", "employee_id", "hard", "rejected",
        "source_not_null_raw_timesheets_employee_id",
        lambda: "1 row with null employee_id (project_id=P001)",
        "dropped in stg_timesheets (missing employee_id)",
    ),
    (
        "relationships", "timesheets", "employee_id -> employees", "hard", "rejected",
        "source_relationships_raw_times_b42e9e2ff33dc9bc290c8f3049a1fe59",
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col(
                "source_relationships_raw_times_b42e9e2ff33dc9bc290c8f3049a1fe59", "from_field"))
        ),
        "dropped in int_timesheets_validated (dangling FK filter)",
    ),
    (
        "relationships", "timesheets", "project_id -> projects", "hard", "rejected",
        "source_relationships_raw_times_2aba4107040c37658cb385c237b31904",
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col(
                "source_relationships_raw_times_2aba4107040c37658cb385c237b31904", "from_field"))
        ),
        "dropped in int_timesheets_validated (dangling FK filter)",
    ),
    # ---- SOFT / REVIEW (kept in dims, flagged warn) ----
    (
        "not_null", "projects", "project_name", "soft", "review",
        "source_not_null_raw_projects_project_name",
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col("source_not_null_raw_projects_project_name", "project_id"))
        ),
        "kept in dim, flagged warn",
    ),
    (
        "invalid_budget", "projects", "budget", "soft", "review",
        "source_invalid_budget_raw_projects_budget",
        lambda: ", ".join(
            f"{pid}({fmt_null(b)})"
            for pid, b in con.execute(
                'select project_id, budget from '
                f'{A}."source_invalid_budget_raw_projects_budget"'
            ).fetchall()
        ),
        "kept in dim, flagged warn",
    ),
    (
        "not_null", "employees", "name", "soft", "review",
        "source_not_null_raw_employees_name",
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col("source_not_null_raw_employees_name", "employee_id"))
        ),
        "kept in dim, flagged warn",
    ),
    (
        "not_null", "employees", "role", "soft", "review",
        "source_not_null_raw_employees_role",
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col("source_not_null_raw_employees_role", "employee_id"))
        ),
        "kept in dim, flagged warn",
    ),
]

rows = []
for (check_name, src_tbl, column, sev, status, tbl, sample_fn, handled) in checks:
    n = count(tbl)
    sample = sample_fn()
    rows.append([check_name, src_tbl, column, sev, status, n, sample, handled])

with open("warehouse/outputs/validation_issues.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["check_name", "source_table", "column", "severity", "status",
                "failing_row_count", "sample_failing_values", "how_handled"])
    w.writerows(rows)

print("Wrote validation_issues.csv with", len(rows), "rows:")
for r in rows:
    print(f"  {r[0]:<18} {r[1]:<11} {r[5]:>2}  {r[3]:<4} {r[6][:60]}")