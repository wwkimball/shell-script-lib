Using Schema Automation Helpers with Docker
===========================================

These schema automation helper scripts support two operating modes:  outside-
and inside-Docker containers.  The intention is to support both:

* Developers who are writing application source code on their local workstations
  against a Docker-based database container.
* Production deployments where the database may or may not be remote yet the
  schema automation needs to be run from within an application container where
  database access credentials are typically available.

When the Database is in a Local Development Container
-----------------------------------------------------

When you need to perform database schema changes from your local workstation
against a locally-running database container that is part of your development
Docker Compose stack, use this method.

This assumes you have cloned this shell script helper library to the `./lib`
directory, a top-level directory in your project.  For the purpose of this
illustration, PostgreSQL will be used and defaults discussed in the base
database `README.me` file are assumed (your DDL files are found in the `./ddl`
top-level directory of your project and so on).  Very similar commands can be
used for any other supported database platform with any other options that are
appropriate for your project.

In addition, this example assumes you are using Docker Secrets for sensitive
values like the PostgreSQL root password.  If not, you can export `PGPASSWORD`
prior to running the `postgresql.sh` helper script.

You can run these commands -- and their rollback counterparts -- as often as you
need to work on your application's database schema.

```bash
# When the root password is in an appropriately-named Docker Secret file:
./lib//database/schema/postgresql.sh \
    --password-file ./docker/secrets/postgresql_root_password.txt

# When you would rather export PGPASSWORD:
export PGPASSWORD='your-postgresql-root-password'
./lib//database/schema/postgresql.sh
unset PGPASSWORD
```

This is the very least you have to do when your project is laid out using the
defaults discussed in `README.md`, your Docker Compose stack defines a database
container named `container`, it is running, and accessible via commands like:
`docker compose exec database ...`.  Such a configuration may look like:

```yaml
name: your-app-stack

services:
  # Other app-specific service containers
  # ...
  database:
    image: postgres:16
    restart: always
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/postgresql_root_password
    secrets:
      - postgresql_root_password
    volumes:
      - database-data:/var/lib/postgresql/data
    profiles:
      - development
    logging:
      options:
        max-size: "5m"
        max-file: "3"

secrets:
  postgresql_root_password:
    file: ./secrets/postgresql_root_password.txt

volumes:
  database-data: {}
```

Note that this configuration specifically dictates that the database container
is a component only of the `development` profile.  This is because non-
development deployments of any project should use centrally-managed or hosted
database platforms, discussed next.

When the Database is Outside Your Compose Stack
-----------------------------------------------

Production and staging deployments use databases that are not part of the
application's Docker Compose stack.  They may be managed (cloud) services,
separate database clusters on the private network, or otherwise hosted on other
machines.  This library supports that model:  the helper scripts can be run from
within any application container that has both network access to the database
and necessary credentials (any account which can create databases, roles, users,
and -- application dependeing -- any other necessary custom data-types, et al).

Key Requirements for this Deployment Pattern
--------------------------------------------

* The application container must include a copy of this shell script library
  somewhere in the container filesystem (the examples below use an
  `INSTALL_DIRECTORY` such as `/opt/your-app` with the library placed in
  `/opt/your-app/lib`).
* The schema definition file (DDL) tree for the target platform must be
  copied into the container at a known location (the example uses
  `/opt/your-app/ddl/postgresql`).  When it will be elsewhere, you must specify
  this alternate directory as an additional option not discussed here (see the
  appropriate README file for details).
* The container environment must provide the database connection information
  and other required variables (examples shown below).  Sensitive values such
  as root passwords should be provided using Docker Secrets or another secure
  secret mechanism; the helper scripts accept a `--password-file` option that
  points to the mounted secret file.  It can also use an environment variable
  like `PGPASSWORD` (also database platform specific; see the `--help` output
  of the appropriate helper script for the full list of supported environment
  variables).
* There must be an entry point script (or a bootstrap script called from the
  container's `ENTRYPOINT`) that invokes the schema helper prior to starting the
  application process.  Doing so ensures the schema is up-to-date every time the
  application starts.

Minimal Example:  Required In-Container Layout and Environment
--------------------------------------------------------------

This tooling only requires the container to expose these artifacts/values at
runtime (paths and names may be changed — update the `ENTRYPOINT` config to
match):

* A copy of the shell script library at `${INSTALL_DIRECTORY}/lib` (contains at
  least `shell-helpers.sh` and the `database/schema` helper scripts).
* A copy of your project's DDL directory tree at `/opt/your-app/ddl` (or an
  alternate location you choose as long as you use the `--ddl-directory`
  option).
* Environment variables (or secrets/files) similar to the following:

```bash
# Example ENVs expected by the bootstrap snippet
POSTFIXADMIN_DB_HOST=your.database.host
POSTFIXADMIN_DB_PORT=5432
POSTFIXADMIN_DB_NAME=postfixadmin
INSTALL_DIRECTORY=/opt/your-app
```

Sample ENTRYPOINT Snippet
-------------------------

Place a script similar to the snippet below in your image and make it the
container's ENTRYPOINT (or call it from your entry-point/bootstrap process).
This exact snippet is the recommended minimal set of commands; you may add other
bootstrap tasks (migrations, config templating, user creation, etc.) before
or after the schema update as needed, but keep the schema update call intact.

```bash
# Constants
LIB_DIRECTORY="${INSTALL_DIRECTORY}/lib"
readonly LIB_DIRECTORY

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
    echo "ERROR:  Failed to import shell helpers!" >&2
    exit 2
fi

# Keep the database schema up-to-date.  Notes:
# - The deployment stage must be any supported value other than "development".
#   Otherwise, the script will incorrectly assume that it is running on the bare
#   developer's workstation rather than from within a Docker container.
"${LIB_DIRECTORY}"/database/schema/postgresql.sh \
    --stage production \
    --db-host "${POSTFIXADMIN_DB_HOST}" \
    --db-port "${POSTFIXADMIN_DB_PORT}" \
    --db-user postgres \
    --password-file /run/secrets/postgresql_root_password \
    --default-db-name "${POSTFIXADMIN_DB_NAME}" \
    --ddl-directory /opt/your-app/ddl/postgresql
if [ 0 -ne $? ]; then
    errorOut 1 "Database schema update failed; aborting bootstrap."
fi
logInfo "Database schema update completed successfully."

# Any other commands ultimately running `exec` to transfer execution control to
# the application.
exec ...
```

Note that this command is more verbose than the development version.  It needs
to specify the remote database connection settings and where -- within the
container -- the database schema files reside.  The suggested database user,
`postgres` can be any other username or role your application is allowed to use
with sufficient permissions to create and otherwise manage schema and related
assets.
