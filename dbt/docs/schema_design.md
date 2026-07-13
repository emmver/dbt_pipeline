# Task 4 — Data Model & Schema Design

Star schema for the timesheet warehouse, materialized in schema `main_marts`
inside `warehouse/dbt_pipeline.duckdb`. Source data flows `main_raw` (Python-loaded) →
`main_staging` / `main_intermediate` (cleaned) → `main_marts` (joined + aggregated).

## 1. ER overview

Four entities in `main_marts` (see `dbt/docs/er_diagram.mmd`):

- **`dim_projects`** — project dimension (35 rows). PK `project_id`.
- **`dim_employees`** — employee dimension (40 rows). PK `employee_id`.
- **`fct_timesheets`** — denormalized fact (331 rows). PK `timesheet_id`;
  FK `employee_id` → `dim_employees`; FK `project_id` → `dim_projects`. Dimension
  attributes (`employee_name`, `employee_role`, `project_name`,
  `project_budget`) are joined in for query convenience.
- **`agg_hours_per_project`** — project-level rollup (21 rows). PK `project_id`.

Relationships (both 1—to—many):

- `PROJECTS ||--o{ TIMESHEETS : "has"` — a project has many timesheets.
- `EMPLOYEES ||--o{ TIMESHEETS : "logs"` — an employee logs many timesheets.

```
dim_projects 1 ──< N fct_timesheets N >── 1 dim_employees
                          |
                          v
                 agg_hours_per_project (rollup by project_id)
```

## 2. Proposed schema

Full DDL with intended constraints lives in `warehouse/schema.sql`. Summary:

| Table | PK | FK | Key constraints |
|---|---|---|---|
| `dim_projects` | `project_id` | — | `budget IS NULL OR budget >= 0` |
| `dim_employees` | `employee_id` | — | soft cols (`name`, `role`) nullable |
| `fct_timesheets` | `timesheet_id` | `employee_id`→`dim_employees`; `project_id`→`dim_projects` | `date NOT NULL`; `hours NOT NULL`; `hours > 0 AND hours <= 24` |
| `agg_hours_per_project` | `project_id` | `project_id`→`dim_projects` | `total_hours NOT NULL` |
| `agg_hours_per_project_monthly` | (`project_id`,`month`) | `project_id`→`dim_projects` | `total_hours NOT NULL`; time-trend rollup |
| `rpt_project_economics` | `project_id` | `project_id`→`dim_projects` | `budget_per_hour` derived (assumes budget ≈ labor cost) |

Column types match the live warehouse exactly (verified via
`DESCRIBE main_marts.<table>`):

- `dim_projects`: `project_id VARCHAR`, `project_name VARCHAR`, `budget DECIMAL(12,2)`
- `dim_employees`: `employee_id VARCHAR`, `name VARCHAR`, `role VARCHAR`
- `fct_timesheets`: `timesheet_id VARCHAR`, `employee_id VARCHAR`, `employee_name VARCHAR`, `employee_role VARCHAR`, `project_id VARCHAR`, `project_name VARCHAR`, `project_budget DECIMAL(12,2)`, `date DATE`, `hours DECIMAL(5,2)`
- `agg_hours_per_project`: `project_id VARCHAR`, `project_name VARCHAR`, `timesheet_count INTEGER`, `total_hours DECIMAL(12,2)`, `distinct_employees INTEGER`

## 3. DB-vs-pipeline enforcement

| Check | Enforced where | Mechanism | Notes |
|---|---|---|---|
| PK uniqueness + not-null | DB (build time) | DuckDB `PRIMARY KEY` constraint | Idempotent: no cross-table dependency, so `CREATE OR REPLACE` re-runs succeed. Verified in `information_schema.table_constraints` (PK on all four tables); dup/null inserts blocked. |
| FK referential integrity | Pipeline + test (not DB) | `int_timesheets_validated` semi-join filter (prevention) + `relationships` tests (detection) | A DB `FOREIGN KEY` renders and DuckDB enforces it, but it **breaks idempotent re-runs** ("Cannot alter entry because entries depend on it" — dbt-duckdb #425): the dim can't be CREATE-OR-REPLACEd while the fact's FK references it. Cross-DB `ref()` prefix bug worked around with an expression-based FK, but idempotency issue remained. |
| Value range — `hours` | Pipeline + test | staging/intermediate filters (`hours > 0 AND hours <= 24`) + source custom range test | Intended `CHECK` declared in `schema.sql`; not materialized as a DB constraint. |
| Value range — `budget` | Pipeline + test | staging nulls bad budget + `budget IS NULL OR budget >= 0` source test | Intended `CHECK` declared in `schema.sql`. |
| Value range — `date` | Pipeline + test | intermediate date-validity filter + source date test | — |
| Soft / review nulls (`name`, `role`, `budget`) | Test (warn) | warn-severity `not_null`-style tests | NOT a DB constraint: a `NOT NULL` would hard-fail the build on the intentionally-kept review rows (valid id, suspect attribute). Warn tests surface them without dropping. |
| Source duplicates / missing ids / bad hours / dangling FKs | Source test + audit | `unique` / `not_null` / `accepted_values` / custom range / `relationships` tests on `main_raw` with `store_failures` → `main_dbt_test__audit` | Source-quality report; not a data product. |
| `total_hours NOT NULL` (agg) | DB (build time) | DuckDB CHECK constraint (materialized) | Verified in `information_schema.table_constraints` (`agg_hours_per_project_total_hours_not_null`). |

## 4. Assumptions & trade-offs

1. **No validation fact in the DAG.** Validation output is the dbt test
   failures audit (`main_dbt_test__audit`, via `store_failures`) plus the CSV
   export — a *report*, not a data product. There is no `fct_validation_issues`
   model in the DAG; tests + `store_failures` replace it.
2. **Dedup in staging.** Source-level cleaning follows dbt-Labs guidance
   (single-source cleaning belongs in staging). All rows are retained in the
   staging model with a `dup_rank` window column so the audit can report
   duplicates; only rank-1 rows flow onward.
3. **No separate `int_` model for dimension validation.** Per the dbt
   convention that "intermediate connects atomic sources," dimension
   validation lives inside the `dim_*` models and the test suite (the
   `fct_validation_issues` idea is replaced by warn-severity tests), not in a
   dedicated intermediate model.
4. **DuckDB FK idempotency trade-off.** A declared FK constraint breaks
   `CREATE OR REPLACE` re-runs in DuckDB (issue #425). FK integrity is
   therefore enforced by the pipeline (semi-join filter in
   `int_timesheets_validated`) and detected by `relationships` tests, not by a
   DB constraint. The FK is declared in `schema.sql` as the *intended* design.
5. **Soft "review" rows are kept, not dropped.** Dimension rows with a valid
   id but a suspect attribute (null `name`/`role`/`budget`) are retained and
   surfaced by warn-severity tests, so the analyst can review them rather than
   silently losing data.
6. **md5 surrogate `timesheet_id`.** The fact PK is an md5 hash of the natural
   timesheet key, giving a stable, collision-resistant PK independent of
   source-row ordering.
7. **Run pattern is `dbt run` then `dbt test`.** `dbt build` is avoided because
   dbt-Fusion skips downstream models when upstream/source tests error, which
   would silently drop mart builds. `run` + `test` keeps model materialization
   and test execution decoupled.