-- ============================================================================
-- dbt pipeline — Task 4: INTENDED relational schema (design doc)
-- Schema: main_marts  (DuckDB warehouse: warehouse/dbt_pipeline.duckdb)
-- ============================================================================
-- This file documents the *intended* relational schema: what we would enforce
-- in a warehouse that fully supports declarative constraints.
--
-- What IS enforced in the current DuckDB + dbt stack:
--   * PRIMARY KEY  — yes. DuckDB primary_key constraints are created on every
--     PK column (verified in information_schema.table_constraints). They are
--     idempotent: no cross-table dependency, so CREATE OR REPLACE TABLE works
--     on re-runs. Duplicate/null PK inserts are blocked at build time.
--   * CHECK (not_null) on PK columns — yes, materialized automatically as
--     `..._not_null` CHECK constraints alongside the PK.
--   * CHECK (total_hours IS NOT NULL) on agg — yes (materialized).
--
-- What is NOT enforced by a DB constraint in the current stack:
--   * FOREIGN KEY — dbt renders it and DuckDB enforces it, BUT it breaks
--     idempotent re-runs in DuckDB ("Cannot alter entry because entries depend
--     on it" — dbt-duckdb issue #425): the dim cannot be CREATE-OR-REPLACEd
--     while the fact's FK references it. A cross-database FK rendering bug
--     (dbt's ref() includes the DB prefix) was worked around with an
--     expression-based FK, but the idempotency issue remained. FK integrity is
--     therefore enforced by the PIPELINE (int_timesheets_validated filters
--     dangling rows via a semi-join to the dims — prevention) and DETECTED by
--     dbt `relationships` tests (post-build). FK is declared below for design
--     completeness; it is not materialized in the live warehouse.
--   * NOT NULL on fct.date / fct.hours — declared below as the intended design;
--     the materialized fct leaves them nullable because the pipeline already
--     guarantees non-null/ranged values and a hard constraint would convert
--     any future regression into a build failure rather than a test warning.
--   * CHECK (hours > 0 AND hours <= 24) and (budget IS NULL OR budget >= 0) —
--     intended checks; enforced in the live stack by pipeline filters
--     (staging/intermediate) + source custom tests, not by DB constraints.
--   * NOT NULL on soft/review columns (project_name, name, role, budget) —
--     intentionally NOT declared. These columns carry intentionally-kept
--     "review" rows (valid id, suspect attribute). A NOT NULL constraint
--     would hard-fail the build on those rows. Soft issues are surfaced by
--     warn-severity dbt tests instead.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- dim_projects
-- ----------------------------------------------------------------------------
CREATE TABLE main_marts.dim_projects (
    project_id   VARCHAR       NOT NULL,
    project_name VARCHAR,                       -- nullable: review rows
    budget       DECIMAL(12,2),                  -- nullable: review rows
    CONSTRAINT dim_projects_project_id_pkey PRIMARY KEY (project_id),
    CONSTRAINT dim_projects_budget_nonneg CHECK (budget IS NULL OR budget >= 0)
);

-- ----------------------------------------------------------------------------
-- dim_employees
-- ----------------------------------------------------------------------------
CREATE TABLE main_marts.dim_employees (
    employee_id VARCHAR NOT NULL,
    name        VARCHAR,                         -- nullable: review rows
    role        VARCHAR,                         -- nullable: review rows
    CONSTRAINT dim_employees_employee_id_pkey PRIMARY KEY (employee_id)
);

-- ----------------------------------------------------------------------------
-- fct_timesheets  (denormalized fact — dims joined in)
-- ----------------------------------------------------------------------------
CREATE TABLE main_marts.fct_timesheets (
    timesheet_id    VARCHAR       NOT NULL,
    employee_id     VARCHAR,                      -- FK -> dim_employees
    employee_name   VARCHAR,                      -- denormalized
    employee_role   VARCHAR,                      -- denormalized
    project_id      VARCHAR,                      -- FK -> dim_projects
    project_name    VARCHAR,                      -- denormalized
    project_budget  DECIMAL(12,2),                -- denormalized
    date            DATE          NOT NULL,
    hours           DECIMAL(5,2)  NOT NULL,
    CONSTRAINT fct_timesheets_timesheet_id_pkey PRIMARY KEY (timesheet_id),
    CONSTRAINT fct_timesheets_employee_id_fkey
        FOREIGN KEY (employee_id) REFERENCES main_marts.dim_employees(employee_id),
    CONSTRAINT fct_timesheets_project_id_fkey
        FOREIGN KEY (project_id) REFERENCES main_marts.dim_projects(project_id),
    CONSTRAINT fct_timesheets_hours_range CHECK (hours > 0 AND hours <= 24)
);

-- ----------------------------------------------------------------------------
-- agg_hours_per_project
-- ----------------------------------------------------------------------------
CREATE TABLE main_marts.agg_hours_per_project (
    project_id         VARCHAR       NOT NULL,
    project_name       VARCHAR,                      -- nullable
    timesheet_count    INTEGER,
    total_hours        DECIMAL(12,2) NOT NULL,
    distinct_employees INTEGER,
    CONSTRAINT agg_hours_per_project_project_id_pkey PRIMARY KEY (project_id),
    CONSTRAINT agg_hours_per_project_project_id_fkey
        FOREIGN KEY (project_id) REFERENCES main_marts.dim_projects(project_id)
);

-- ----------------------------------------------------------------------------
-- agg_hours_per_project_monthly  (time-trend rollup: project x month)
-- ----------------------------------------------------------------------------
CREATE TABLE main_marts.agg_hours_per_project_monthly (
    project_id          VARCHAR       NOT NULL,
    month               DATE         NOT NULL,
    project_name        VARCHAR,
    timesheet_count     INTEGER      NOT NULL,
    total_hours         DECIMAL(12,2) NOT NULL,
    distinct_employees  INTEGER      NOT NULL,
    CONSTRAINT agg_hours_per_project_monthly_pkey PRIMARY KEY (project_id, month),
    CONSTRAINT agg_hours_per_project_monthly_fkey
        FOREIGN KEY (project_id) REFERENCES main_marts.dim_projects(project_id)
);

-- ----------------------------------------------------------------------------
-- rpt_project_economics  (per-project budget vs hours; budget_per_hour = budget/total_hours)
-- NOTE: budget_per_hour assumes `budget` is a labor-cost budget comparable to
-- hours; if budget is a total project budget, treat it as indicative only.
-- ----------------------------------------------------------------------------
CREATE TABLE main_marts.rpt_project_economics (
    project_id          VARCHAR       NOT NULL,
    project_name        VARCHAR,
    budget              DECIMAL(12,2),                -- nullable: review rows
    total_hours         DECIMAL(12,2) NOT NULL,      -- 0 for projects with no timesheets
    distinct_employees  INTEGER       NOT NULL,
    budget_per_hour     DECIMAL(18,4),                -- nullable: no hours or null budget
    CONSTRAINT rpt_project_economics_pkey PRIMARY KEY (project_id),
    CONSTRAINT rpt_project_economics_fkey
        FOREIGN KEY (project_id) REFERENCES main_marts.dim_projects(project_id)
);
