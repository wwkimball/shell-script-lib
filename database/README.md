Database Schema Automation Helpers
==================================

These helper scripts automate applying and rolling back database schema
changes via structured Schema Description Files.  There is an implementation
script for each supported database platform.

*IMPORTANT*:  Always perform a full, verified backup of any target database
before running schema changes with these scripts.  Schema changes may be
destructive and some rollbacks cannot be accomplished without restoring from
backup.  Note that these scripts neither create nor utilize backups.

How DDL Files are Structured and Named
--------------------------------------

Files must be named to match the schema version they represent using this
format (note that the `ddl` extension is the default but can be set to anything
else you prefer via the `--ddl-extension` option):

> `YYYYMMDD-N.ddl`

Where:

- `YYYY`:  4-digit year
- `MM`:  2-digit month (zero-padded)
- `DD`:  2-digit day (zero-padded)
- `N`:  increasing serial number for multiple files created on the same day

These scripts discover files in a specified directory and run them in
numeric/chronological order informed by following this naming convention.

Each forward-change file must have a corresponding rollback file named
`YYYYMMDD-N.rollback.ddl` containing DDL which reverses the change (where
possible).  These scripts track files that have successfully run and will
attempt to run rollback files in reverse order when the operation is aborted
(for example, via Ctrl+C) or when a fatal error occurs.

Header Block
------------

A DDL file may contain a header comment specifying which database to run the
file against.  The script looks for a header line like:

```sql
-- database: target_database_name
```

When that header is absent, the default database provided via command-line or
environment variable is used.

The remainder of the file may contain any valid DDL.

File Organization Recommendation
--------------------------------

To keep projects consistent and easy to automate, use one of these layouts for
DDL files.  The default top-level directory is `./ddl`.  You may choose any
context-appropraite top-level directory name, instead via the `--ddl-directory`
option.  Remember at all times that the following is a recommendation and not a
requirement.

Single platform (only one database type required):

```text
/ddl
```

Multiple platforms (projects supporting both MySQL and PostgreSQL):

```text
/ddl/mysql
/ddl/postgresql
```

Under each platform directory, organize files by year and month to avoid very
large directories (which may cause operating system limitation issues) and to
keep file ordering numeric and predictable.  For example:

```text
/ddl/mysql/2025/05/20250518-1.ddl
/ddl/mysql/2025/05/20250518-1.rollback.ddl
```

This structure ensures the directory sizes remain manageable and that the files
sort in numerical/chronological order automatically.

Safety and Rollback Guidance
----------------------------

1) Full backup:  Always create a full backup and verify it before running
   schema changes.  Without a backup, some schema changes cannot be undone by
   the rollback files alone.

2) Test locally:  Use a local Docker Compose development environment (the
   script can automatically use Docker Compose when it detects the project
   layout) to run DDL changes against a disposable database instance, first.

3) Remember that these scripts run every DDL file in a transaction.  Rely on
   this only for edge-case issues.  There are certain commands which cannot run
   within a transaction.  Whenever a transaction fails due to this, these
   scripts will re-run the affected file without a transaction.

4) Prefer safe, reversible operations.  When a change will transform or move
   data, use a temporary table to perform the transformation.  Only after
   validating the transformed data should you replace the original.  This
   reduces the risk of data loss during schema changes, especially when issues
   would not trigger a transaction error.

5) For destructive changes (for example, dropping a column or table), document
   the risk and on failure, require a backup restore to return to the previous
   state.  Rollback files cannot recover data that was deliberately removed by
   forward DDL files; they can only recreate schema objects as specified in the
   DDL.

6) Also for destructive operations, consider deferring the operation to a later
   version of your application.  Operation which carry great risk of data loss
   should only be performed once you have definitively ruled out any chance that
   a rollback might be needed.  Note that you can always restore from a full
   backup anyway, but deferring the data destruction at least one application
   version greatly reduces other risks associated with performing a database
   restore (namely, losing all data created since the backup was performed).

7) Use the `--force` option only intentionally.  Downgrades (rolling back to an
   earlier schema version) require `--force` to prevent accidental data loss.

Generic Example Layouts and Starter DDL
---------------------------------------

The platform-specific README files contain generic example layouts and minimal
starter DDL and rollback snippets you can use as a starting point for your own
projects.  Concrete examples and recommended starter DDL files are included for
creating the mandatory `settings` table.

Where to Go Next
----------------

- See `README-MySQL.md` for detailed instructions and examples for MySQL.
- See `README-PostgreSQL.md` for detailed instructions and examples for
  PostgreSQL.
