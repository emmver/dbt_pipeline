"""
Raw load stage.

Reads the three source CSVs from data/ and lands them verbatim into the
`main_raw` schema of a DuckDB warehouse. No cleaning, no type coercion: every
column is stored as VARCHAR so the raw layer is a faithful copy of the
source files. Validation and typing happen in later (staging) stages.

Idempotent: tables are recreated (CREATE OR REPLACE) on every run, so the
pipeline can be rerun without producing inconsistent results.
"""

from pathlib import Path

import duckdb

# Project paths
ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
WAREHOUSE = ROOT / "warehouse" / "dbt_pipeline.duckdb"

# Source files -> target table names
SOURCES = {
    "projects.csv": "projects",
    "employees.csv": "employees",
    "timesheets.csv": "timesheets",
}

# Explicit raw schema: all VARCHAR, faithful to source.
RAW_COLUMNS = {
    "projects": [
        ("project_id", "VARCHAR"),
        ("project_name", "VARCHAR"),
        ("budget", "VARCHAR"),
    ],
    "employees": [
        ("employee_id", "VARCHAR"),
        ("name", "VARCHAR"),
        ("role", "VARCHAR"),
    ],
    "timesheets": [
        ("employee_id", "VARCHAR"),
        ("project_id", "VARCHAR"),
        ("date", "VARCHAR"),
        ("hours", "VARCHAR"),
    ],
}


def load_raw(con: duckdb.DuckDBPyConnection) -> None:
    # `main_raw` mirrors dbt's default `main_<schema>` naming so the four
    # pipeline layers are symmetric siblings: main_raw / main_staging /
    # main_intermediate / main_marts.
    con.execute("CREATE SCHEMA IF NOT EXISTS main_raw")

    for filename, table in SOURCES.items():
        csv_path = DATA_DIR / filename
        if not csv_path.exists():
            raise FileNotFoundError(f"Source CSV not found: {csv_path}")

        columns = RAW_COLUMNS[table]
        col_defs = ", ".join(f"{name} {dtype}" for name, dtype in columns)

        # CREATE OR REPLACE guarantees a clean, idempotent reload every run.
        con.execute(f"CREATE OR REPLACE TABLE main_raw.{table} ({col_defs})")

        # read_csv with header=True and all_varchar=True so DuckDB does not
        # infer types or drop/mangle anything. We insert into the pre-typed
        # table to be explicit.
        con.execute(
            f"""
            INSERT INTO main_raw.{table}
            SELECT * FROM read_csv_auto(
                '{csv_path.as_posix()}',
                header = true,
                all_varchar = true
            )
            """
        )

        count = con.execute(f"SELECT COUNT(*) FROM main_raw.{table}").fetchone()[0]
        print(f"main_raw.{table}: {count} rows loaded from {filename}")


def main() -> None:
    WAREHOUSE.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(WAREHOUSE))
    try:
        load_raw(con)
    finally:
        con.close()


if __name__ == "__main__":
    main()