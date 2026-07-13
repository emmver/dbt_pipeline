"""Build warehouse/outputs/validation_issues.csv (Task 2 deliverable).

Counts and sample failing values are QUERIED from main_dbt_test__audit (and the
warehouse where helpful) -- not hand-typed. Audit tables are discovered by
prefix so the script is robust to dbt's hashed table-name suffixes changing
when a test definition changes.
"""
import csv
import duckdb

con = duckdb.connect("warehouse/dbt_pipeline.duckdb", read_only=True)
A = "main_dbt_test__audit"


def tables():
    return {
        r[0]
        for r in con.execute(
            "select table_name from information_schema.tables "
            "where table_schema = 'main_dbt_test__audit'"
        ).fetchall()
    }


def find_table(prefix):
    """Return the single audit table whose name starts with prefix."""
    matches = [t for t in tables() if t.startswith(prefix)]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected exactly one audit table starting with {prefix!r}, "
            f"found {matches}"
        )
    return matches[0]


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


# The two raw timesheets relationships tests share a prefix; disambiguate by
# inspecting the failing from_field values (employee ids start with 'E',
# project ids with 'P').
def relationships_tables():
    cands = [t for t in tables() if t.startswith("source_relationships_raw_times_")]
    emp_tbl = proj_tbl = None
    for t in cands:
        vals = [v or "" for v in col(t, "from_field")]
        if any(str(v).startswith("E") for v in vals):
            emp_tbl = t
        elif any(str(v).startswith("P") for v in vals):
            proj_tbl = t
    if not emp_tbl or not proj_tbl:
        raise RuntimeError(f"could not disambiguate relationships tables: {cands}")
    return emp_tbl, proj_tbl


_REL_EMP, _REL_PROJ = relationships_tables()

# Each entry: (check_name, source_table, column, severity, status, table,
#             sample_fn, how_handled)
checks = [
    # ---- HARD / REJECTED ----
    (
        "unique", "projects", "project_id", "hard", "rejected",
        find_table("source_unique_raw_projects_project_id"),
        lambda: ", ".join(uniq(col(find_table("source_unique_raw_projects_project_id"), "unique_field"))),
        "dropped in stg_projects (dup survivor kept)",
    ),
    (
        "not_null", "projects", "project_id", "hard", "rejected",
        find_table("source_not_null_raw_projects_project_id"),
        lambda: "1 null id row (project_name='Unnamed Initiative')",
        "dropped in stg_projects (null PK row)",
    ),
    (
        "unique", "employees", "employee_id", "hard", "rejected",
        find_table("source_unique_raw_employees_employee_id"),
        lambda: ", ".join(uniq(col(find_table("source_unique_raw_employees_employee_id"), "unique_field"))),
        "dropped in stg_employees (dup survivor kept)",
    ),
    (
        "hours_in_range", "timesheets", "hours", "hard", "rejected",
        find_table("source_hours_in_range_raw_timesheets_hours"),
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col(find_table("source_hours_in_range_raw_timesheets_hours"), "hours"))
        ),
        "dropped in stg_timesheets (single-source reject)",
    ),
    (
        "unique_natural_key", "timesheets", "employee_id+project_id+date", "hard", "rejected",
        find_table("source_unique_natural_key_raw__"),
        lambda: ", ".join(
            f"{r[0]}/{r[1]}/{r[2]}"
            for r in con.execute(
                'select employee_id, project_id, date from '
                f'{A}."{find_table("source_unique_natural_key_raw__")}"'
            ).fetchall()
        ),
        "dropped in stg_timesheets (exact-dup, one row kept per natural key)",
    ),
    (
        "not_null", "timesheets", "employee_id", "hard", "rejected",
        find_table("source_not_null_raw_timesheets_employee_id"),
        lambda: "1 row with null employee_id (project_id=P001)",
        "dropped in stg_timesheets (missing employee_id)",
    ),
    (
        "relationships", "timesheets", "employee_id -> employees", "hard", "rejected",
        _REL_EMP,
        lambda: ", ".join(uniq(fmt_null(v) for v in col(_REL_EMP, "from_field"))),
        "dropped in int_timesheets_validated (dangling FK filter)",
    ),
    (
        "relationships", "timesheets", "project_id -> projects", "hard", "rejected",
        _REL_PROJ,
        lambda: ", ".join(uniq(fmt_null(v) for v in col(_REL_PROJ, "from_field"))),
        "dropped in int_timesheets_validated (dangling FK filter)",
    ),
    # ---- SOFT / REVIEW (kept in dims, flagged warn) ----
    (
        "not_null", "projects", "project_name", "soft", "review",
        find_table("source_not_null_raw_projects_project_name"),
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col(find_table("source_not_null_raw_projects_project_name"), "project_id"))
        ),
        "kept in dim, flagged warn",
    ),
    (
        "invalid_budget", "projects", "budget", "soft", "review",
        find_table("source_invalid_budget_raw_projects_budget"),
        lambda: ", ".join(
            f"{pid}({fmt_null(b)})"
            for pid, b in con.execute(
                'select project_id, budget from '
                f'{A}."{find_table("source_invalid_budget_raw_projects_budget")}"'
            ).fetchall()
        ),
        "kept in dim, flagged warn",
    ),
    (
        "not_null", "employees", "name", "soft", "review",
        find_table("source_not_null_raw_employees_name"),
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col(find_table("source_not_null_raw_employees_name"), "employee_id"))
        ),
        "kept in dim, flagged warn",
    ),
    (
        "not_null", "employees", "role", "soft", "review",
        find_table("source_not_null_raw_employees_role"),
        lambda: ", ".join(
            uniq(fmt_null(v) for v in col(find_table("source_not_null_raw_employees_role"), "employee_id"))
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