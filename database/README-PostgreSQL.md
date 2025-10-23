PostgreSQL Schema Automation
============================

This document explains how to use the `postgresql.sh` helper script located at
`./database/schema/postgresql.sh` to apply or roll back PostgreSQL schema
changes stored as Schema Description Files (DDL files).

*Be sure to read the base `README.md` file for crucial conventions used in this
file.*

**IMPORTANT**:  Always perform a full, verified backup of any target database
before running schema changes with these scripts.  Schema changes may be
destructive and some rollbacks cannot be accomplished without restoring from
backup.  Note that these scripts neither create nor utilize backups.

Invocation and Basic Examples
-----------------------------

Set the database password in the `PGPASSWORD` environment variable or use
`--password-file` to provide the password from a file (the script will export
it as `PGPASSWORD`).  Then run the script from the project root (it derives the
default DDL directory from the project layout).

Examples:

Update schema to the latest available version:

```bash
export PGPASSWORD='your-admin-password'
./database/schema/postgresql.sh
unset PGPASSWORD
```

Update schema to a specific version (format: `YYYYMMDD-N`):

```bash
export PGPASSWORD='your-admin-password'
./database/schema/postgresql.sh 20250512-3
unset PGPASSWORD
```

Downgrade (rollback) to a specific version (requires `--force`):

```bash
export PGPASSWORD='your-admin-password'
./database/schema/postgresql.sh --force 20250510-1
unset PGPASSWORD
```

Destroy and recreate schema (dangerous).  Only do this with reliable rollback
files and a verified backup:

```bash
export PGPASSWORD='your-admin-password'
./database/schema/postgresql.sh --force 00000000-0 && ./database/schema/postgresql.sh
unset PGPASSWORD
```

Important Options
-----------------

- `-h|--db-host HOST`:  Database server hostname (default:  `PGHOST` or
  `database` for local Docker Compose setups).
- `-D|--default-db-name NAME`:  Default database used when a DDL file lacks a
  header specifying the target database (default:  `PGDATABASE`).
- `-u|--db-user USER`:  Superadmin user (default:  `PGUSER` or `postgres`).
- `-p|--db-port PORT`:  Database port (default:  `PGPORT` or 5432).
- `-P|--password-file FILE`:  Read database password from `FILE` instead of
  using `PGPASSWORD` (file content is exported into `PGPASSWORD`).
- `-l|--ddl-directory DIR`:  Directory containing DDL files (default:  `./ddl`
  of the project root).  Files are discovered recursively and run in sorted
  order.
- `-x|--ddl-extension EXT`:  File extension for DDL files (default:  `ddl`).
- `-s|--settings-table TABLE`:  Table name that stores the schema version
  (default: `settings`).
- `-k|--version-key KEY`:  Key name in the settings table used to track schema
  version (default:  `schema_version`).
- `-f|--force`:  Required to perform deliberate rollbacks (prevents accidental
  data loss).

Generic Example Layout and Starter DDL
--------------------------------------

Below is a minimal, generic example layout and a starter pair of DDL and
rollback files for a PostgreSQL-based project.  Place DDL files under
`/ddl/postgresql/YYYY/MM/` as recommended in the top-level README.

Example directory layout:

```text
/ddl/postgresql/
  2025/
    05/
      20250518-1.ddl
      20250518-1.rollback.ddl
      20250518-2.ddl
      20250518-2.rollback.ddl
```

Create the base schema and application admin user as
`/ddl/postgresql/2025/05/20250518-1.ddl`:

```sql
-- database: myapp
--
-- Create application schema and user
-- TODO:  Change the password!
CREATE ROLE myapp_admin LOGIN PASSWORD 'Change-This-Password!';

CREATE DATABASE myapp OWNER myapp_admin;
```

Rollback base schema creation and application admin user as
`/ddl/postgresql/2025/05/20250518-1.rollback.ddl`:

```sql
-- database: myapp
--
-- Note: Dropping the database is destructive; only do this when you are
-- certain it is safe and you have a full backup.
REVOKE CONNECT ON DATABASE myapp FROM public;
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'myapp';
DROP DATABASE IF EXISTS myapp;
DROP ROLE IF EXISTS myapp_admin;
```

Create the settings table (used for schema versioning and can also be used by
your application for any other persistent settings) as
`/ddl/postgresql/2025/05/20250518-2.ddl`:

```sql
-- database: myapp
--
CREATE TABLE IF NOT EXISTS settings (
  name text PRIMARY KEY
  , value text NOT NULL
  , created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
  , updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO settings (name, value) VALUES ('schema_version','20250518-1')
  ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value;
```

Rollback the settings table creation as
`/ddl/postgresql/2025/05/20250518-2.rollback.ddl`:

```sql
-- database: myapp
--
-- Rollback changes:  Drop the settings table
DROP TABLE IF EXISTS settings CASCADE;
```

Note the pattern:  All files are atomic and for every forward DDL change,
there is a matching rollback file.  Avoid creating very large DDL files;
remember that each file is run within a separate transaction.
