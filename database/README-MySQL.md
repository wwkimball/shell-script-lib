MySQL Schema Automation
=======================

This document explains how to use the `mysql.sh` helper script located at
`./database/schema/mysql.sh` to apply or roll back MySQL-compatible schema
changes stored as Schema Description Files (DDL files).

*Be sure to read the base `README.md` file for crucial conventions used in this
file.*

**IMPORTANT**:  Always perform a full, verified backup of any target database
before running schema changes with these scripts.  Schema changes may be
destructive and some rollbacks cannot be accomplished without restoring from
backup.  Note that these scripts neither create nor utilize backups.

Invocation and Basic Examples
-----------------------------

Set the database password in the `MYSQL_PASSWORD` environment variable or use
`--password-file` to provide the password from a file.  Then run the script from
the project root (it derives the default DDL directory from the project
layout).

Examples:

Update schema to the latest available version:

```bash
export MYSQL_PASSWORD='your-admin-password'
./database/schema/mysql.sh
unset MYSQL_PASSWORD
```

Update schema to a specific version (format: `YYYYMMDD-N`):

```bash
export MYSQL_PASSWORD='your-admin-password'
./database/schema/mysql.sh 20250512-3
unset MYSQL_PASSWORD
```

Downgrade (rollback) to a specific version (requires `--force`):

```bash
export MYSQL_PASSWORD='your-admin-password'
./database/schema/mysql.sh --force 20250510-1
unset MYSQL_PASSWORD
```

Destroy and recreate schema (dangerous).  Only do this with reliable rollback
files and a verified backup:

```bash
export MYSQL_PASSWORD='your-admin-password'
./database/schema/mysql.sh --force 00000000-0 && ./database/schema/mysql.sh
unset MYSQL_PASSWORD
```

Important Options
-----------------

- `-h|--db-host HOST`:  Database server hostname (default:  from `MYSQL_HOST` or
  `database` for local Docker Compose setups).
- `-D|--default-db-name NAME`:  Default database used when a DDL file lacks a
  header specifying the target database (default:  `MYSQL_DATABASE`).
- `-u|--db-user USER`:  Superadmin user (default:  `MYSQL_USER` or `root`).
- `-p|--db-port PORT`:  Database port (default:  `MYSQL_PORT` or 3306).
- `-P|--password-file FILE`:  Read database password from `FILE` instead of
  using `MYSQL_PASSWORD`.
- `-l|--ddl-directory DIR`:  Directory containing your tree of DDL files
  (default:  `./ddl` of the project root).  Files are discovered recursively and
  run in sorted order.
- `-x|--ddl-extension EXT`:  File extension for DDL files (default:  `ddl`).
- `-s|--settings-table TABLE`:  Table name that stores the schema version
  (default: `settings`).
- `-k|--version-key KEY`:  Key name in the settings table used to track schema
  version (default:  `schema_version`).
- `-f|--force`:  Required to perform deliberate rollbacks (prevents accidental
  data loss).
- `-T|--no-tls`:  Disable TLS when connecting (useful for local Docker
  development).

Generic Example Layout and Starter DDL
--------------------------------------

Below is a minimal, generic example layout and a starter pair of DDL and
rollback files for a MySQL-based project.  These are intended as a simple
template you can copy into your own project.  Place DDL files under
`/ddl/mysql/YYYY/MM/` as recommended in the top-level README.

Example directory layout:

```text
/ddl/mysql/
  2025/
    05/
      20250518-1.ddl
      20250518-1.rollback.ddl
      20250518-2.ddl
      20250518-2.rollback.ddl
```

Create the base schema and application admin user as
`/ddl/mysql/2025/05/20250518-1.ddl`:

```sql
-- database: myapp
--
-- Create application schema and application user
CREATE DATABASE IF NOT EXISTS `myapp`;

-- TODO:  Change @'%' to an actual source network!
-- TODO:  Change the password!
CREATE USER IF NOT EXISTS 'myapp_admin'@'%' IDENTIFIED BY 'Change-This-Password!';

-- TODO:  Change @'%' to the network identified above!
GRANT ALL PRIVILEGES ON `myapp`.* TO 'myapp_admin'@'%';

FLUSH PRIVILEGES;
```

Rollback base schema creation and application admin user as
`/ddl/mysql/2025/05/20250518-1.rollback.ddl`:

```sql
-- database: myapp
--
-- Note: Dropping the database is destructive; only do this when you are
-- certain it is safe and you have a full backup.
REVOKE ALL PRIVILEGES ON `myapp`.* FROM 'myapp_admin'@'%';

DROP USER IF EXISTS 'myapp_admin'@'%';
DROP DATABASE IF EXISTS `myapp`;
```

Create the settings table (used for schema versioning and can also be used by
your application for any other persistent settings) as
`/ddl/mysql/2025/05/20250518-2.ddl`:

```sql
-- database:  myapp
--
CREATE TABLE IF NOT EXISTS `settings` (
  `name` VARCHAR(255) NOT NULL PRIMARY KEY
  , `value` TEXT NOT NULL
  , `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  , `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO `settings` (`name`,`value`) VALUES ('schema_version', '20250518-1')
  ON DUPLICATE KEY UPDATE `value` = '20250518-1';
;
```

Rollback the settings table creation as
`/ddl/mysql/2025/05/20250518-2.rollback.ddl`:

```sql
-- database: myapp
--
-- Rollback changes:  Drop the settings table
DROP TABLE IF EXISTS `settings`;
```

Note the pattern:  All files are atomic and for every forward DDL change,
there is a matching rollback file.  Avoid creating very large DDL files;
remember that each file is run within a separate transaction.
