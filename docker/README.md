# Adding Docker Support to Your Project

This README illustrates how to add Docker Compose support to any other project
that is built in Linux-based environments.

## Requirements

To use this project, you must be developing in a Linux-based environment with
Bash 4.2 or newer installed (you don't have to use Bash as your shell but Bash
must be installed).  This includes any flavor of Linux, MacOS, and Windows
running [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).

Because Docker Compose uses [YAML](https://yaml.org/) files, you must install
[yamlpath](https://github.com/wwkimball/yamlpath?tab=readme-ov-file#installing)
in order to use the shell scripts recommended by this project to build and
deploy your project.

## Recommended Project Layout

At your project root, use this directory structure:

```text
VERSION      # The SemVer (semantic version) number of your built Docker images
deploy.d/
  files-to-deploy-verbatim-with-your-Docker-images
docker/
  docker-compose.yaml
  .env
  secrets/
    one-file-per-secret-for-compose.txt
  your-service-name/
    Dockerfile
lib/          # git submodule containing the shared shell helpers
build.sh
compose.sh
deploy.sh
start.sh
stop.sh
```

When your stack defines more than one service, add a uniquely-named subdirectory
under `./docker/` for each in addition to `your-service-name`.

## Quick setup checklist

1. Add or update your `.gitignore` file to exclude secrets and build artifacts.

2. Add the shell script helper submodule at `./lib/`.

3. Create a top-level `VERSION` file containing a single version string
   (for example `0.1.0`).

4. Add a top-level `./docker/` directory.

5. Add `./docker/.env` with only the variables Docker Compose requires.

6. Add the wrapper scripts shown below at the repository root and make
   them executable (for example: `chmod +x *.sh`).

7. Should you have additional scripts or other static content that must be
   deployed with your Docker image, create top-level directory, `./deploy.d/`
   and add your deployment files to it.  Any directory structure you create
   within this directory will be published as-is.

## Your .gitignore File

This project creates build artifacts, supports local-only files, and supports
secrets that must never be added to source code repositories.  As such, you must
have a `.gitignore` file in the top-most directory of your project with at least
the following content:

```text
# Log files
*.log

# Exported Docker volumes (for development, only)
/volumes

# Portable Docker image files
docker/images/

# Docker configuration files with unencrypted secrets
.env*
docker/secrets/

# Baked Docker Compose configuration files
*.baked.yaml

# Docker Compose configuration files for private Lab environments
docker/docker-compose.lab.yaml
```

This is a minimal file.  It should contain other skeleton masks for media files,
other secrets like TLS certificates, thumbnail files, and so on.

## Adding the Standard Shell Script submodule

Add the shared shell helper library as a submodule (example) at the top-level
directory of your project, usually in the `./lib/` directory.  These commands
should be used:

```bash
git submodule add -b master git@github.com:wwkimball/shell-script-lib.git lib
git submodule update --init --recursive
```

**IMPORTANT**:  If you clone this project anywhere other than to `./lib/`, be
sure to set the `STD_SHELL_LIB` environment variable of your shell to the fully-
qualified path to wherever you actually cloned it to!  Failing this may cause
components of the library -- and the recommended sample scripts below -- to
fail as they try to import each other.

You should then immediately commit and push your repository because adding any
submodule makes a change to the `.gitmodules` file (and adds the commit hash a
 `./lib/`) that you need to preserve.

If you use a different host or fork, replace the URL above accordingly.  If you
would prefer to pin the submodule to a stable release, replace `master` after
the `-b` option to the precise `release/*` version you require.  Note that this
is a strong recommendation since `master` will change over time, possibly in
breaking ways.

## Image Versioning

The `VERSION` file contains the base version number, usually in
[SemVer](https://semver.org/) format (`MAJOR.MINOR.PATCH`).  The shell script
library will automatically append a sequential `-BUILD` to your version number.
This ensures that every image you build will have a unique version number no
matter how many times you build it.  This build number is internally tracked by
the library to the value in `VERSION`, so it will always be `-1` for each unique
base version and switching back to a previous version number will resume that
version's sequenced build number.  This build number suffix is SemVer-compliant.

You can control in what directory this versioning data is stored by setting the
`VERSION_DATA_DIR` environment variable.  This enables you to backup the
data directory.

The complete version number is exported to Docker as the `VERSION` environment
variable.

## Docker Compose Configuration File Template

Replace `your-stack-name` with the real, unique name of your Docker Compose
stack.  Be careful that this value is truly unique.  When it is shared with any
other Docker Compose stack running on the target host, the two stacks **will**
interfere with one another such that when one goes up, the other will go down,
and vice-versa.  Also, replace `your-service-name` with the real service name.
This name must be unique only within the same stack.  The `build` block should
reference the per-service directory structure (containing the target
`Dockerfile` and any image-specific configuration files) under `./docker/`.

```yaml
name: your-stack-name

services:
  your-service-name:
    image: ${DOCKER_REGISTRY_SOCKET}/${DOCKER_REGISTRY_USER}/your-service-name:${VERSION:-latest}
    container_name: your-service-name
    build:
      context: ../
      dockerfile: ./docker/your-service-name/Dockerfile
    restart: unless-stopped
    logging:
      options:
        max-size: "5m"
        max-file: "3"
```

Notes:

1. **ALWAYS** have a `logging` section.  Without it, the `STDOUT` and
   `STDERR` output of your image will force Docker to create permanent log files
   that grow *unbounded* on the host.  This inevitably consumes 100% of the
   host's storage, causing fatal errors that take down the host or its ability
   to run Docker containers.
2. You *should* also have a `healthcheck` section so that the host can attempt
   to remediate or report issues with your running containers.

### Override for Deployment Stage

When your project needs a different stack configuration based on a target
deployment stage (development, lab, qa, staging, or production), create an
additional Docker Compose configuration named for it using this naming template:

`docker-compose.stage-name.yaml`

WHERE:

* `stage-name` is the lower-case name of the target deployment stage.

This is especially useful when you need a local service for your development
environment (like a database server) that is otherwise external to the stack for
your staging and/or production environments.  It is also necessary when other
environments utilize permanent assets like NAS resources that are not available
during development.

## Example Dockerfile (place under `./docker/your-service-name/Dockerfile`)

Adjust the base image and build/runtime steps for your application.

```dockerfile
FROM your-base-image:version

# Set working directory
WORKDIR /app

# Copy application files; note that Docker will be running commands from the
# top-level directory of the project, NOT from the ./docker/your-service-name
# directory.
COPY ./your-project-source/ .

# Install dependencies and configure the image
RUN your-install-command

# Expose ports (if any)
EXPOSE your-port

# Expose volumes (if any)
VOLUME ["/app/data"]

# Start commands (the ENTRYPOINT is optional)
ENTRYPOINT ["your-entrypoint-script"]
CMD ["your-start-command-passed-to-your-entrypoint-script"]
```

## Environment Variable Files

This template provides for a seperation between configuration for Docker itself
and your application.  Base configuration for Docker should be kept in the
`./docker/.env` file whereas application-specific configuration should be kept
in `./docker/.env.your-service-name`.  Specialized files for deployment stages
(development, lab, qa, staging, and production) are also supported, like
`./docker/.env.staging`, `./docker/.env.your-service-name.production`, and so
on.

### docker/.env example

Do not store application config in this file; this file is used by Docker
Compose to set variables it needs to build and deploy your project.  When you
create a variable in the base `docker-compose.yaml` file, it must be defined in
this `.env` file (except for `VERSION` which is discussed above).

```env
DOCKER_REGISTRY_SOCKET=registry.example.com
DOCKER_REGISTRY_USER=myuser
```

Deployment stage specific, general environment variables can also be defined in
override files like `.env.development`, `.env.staging`, and so on.  These are
read in a heirarchical fashion with values in deployment stage specific files
overriding the value of same-named variables in `.env`.

Your application's environment variables should be defined in other variable
files like `.env.your-service-name`.  Deployment stage specific files are
supported, like `.env.your-service-name.development`,
`.env.your-service-name.production`, and so on.  The same heirarchical
precedence order exists for these files as with the general `.env` and its
deployment stage specific override files.

### Environment Variable Naming

Environment variable names defined in all `.env*` files must be valid for use
with shell scripts.  This is strictly enforced.

Some parts of the standard shell script library support environment variable
disambiguation.  For these cases, you can define an ambiguous variable like
`MY_VARIABLE` with deployment stage specific override variables,
`MY_VARIABLE_STAGING`, `MY_VARIABLE_PRODUCTION`, and so on.  The library will
disambiguate `MY_VARIABLE` at run-time, overriding the value of the variable
with that of the one whose name ends with and underscore (`_`) followed by the
current value of `DEPLOYMENT_STAGE`.  This is a convenience for CI systems which
are responsible for deployment to multiple deployment stages.

## Helper Scripts

Provide small wrapper scripts at the repository root that source the shared
`lib` helpers and then `exec` the Docker helper scripts in `lib/docker/`.

Example `build.sh`:

```bash
#!/usr/bin/env bash
################################################################################
# Build Docker image(s) for this project using the standard shell script
# library.
#
# Pass a `--help` flag to this script to get comprehensive documentation.
################################################################################
# Constants
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIRECTORY="${STD_SHELL_LIB:-"${MY_DIRECTORY}/lib"}"
DOCKER_HELPER_DIRECTORY="${LIB_DIRECTORY}/docker"
readonly MY_DIRECTORY LIB_DIRECTORY DOCKER_HELPER_DIRECTORY

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
    echo "ERROR:  Failed to import shell helpers!" >&2
    exit 2
fi

# Pass control to the docker helper script
exec "${DOCKER_HELPER_DIRECTORY}/compose-build.sh" "$@"
```

Example `compose.sh`:

```bash
#!/usr/bin/env bash
################################################################################
# Run an arbitrary command against the stack using the standard shell script
# library.
#
# Pass a `--help` flag to this script to get comprehensive documentation.
################################################################################
# Constants
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIRECTORY="${STD_SHELL_LIB:-"${MY_DIRECTORY}/lib"}"
DOCKER_HELPER_DIRECTORY="${LIB_DIRECTORY}/docker"
readonly MY_DIRECTORY LIB_DIRECTORY DOCKER_HELPER_DIRECTORY

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
    echo "ERROR:  Failed to import shell helpers!" >&2
    exit 2
fi

# Pass control to the docker helper script
exec "${DOCKER_HELPER_DIRECTORY}/compose-command.sh" "$@"
```

Example `deploy.sh`:

```bash
#!/usr/bin/env bash
################################################################################
# Deploy any Docker image(s) for this project to remote hosts using the standard
# shell script library.
#
# Pass a `--help` flag to this script to get comprehensive documentation.
################################################################################
# Constants
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIRECTORY="${STD_SHELL_LIB:-"${MY_DIRECTORY}/lib"}"
DOCKER_HELPER_DIRECTORY="${LIB_DIRECTORY}/docker"
readonly MY_DIRECTORY LIB_DIRECTORY DOCKER_HELPER_DIRECTORY

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
    echo "ERROR:  Failed to import shell helpers!" >&2
    exit 2
fi

# Pass control to the docker helper script
exec "${DOCKER_HELPER_DIRECTORY}/compose-deploy.sh" "$@"
```

Example `start.sh`:

```bash
#!/usr/bin/env bash
################################################################################
# Start the stack using the standard shell script library.
#
# Pass a `--help` flag to this script to get comprehensive documentation.
################################################################################
# Constants
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIRECTORY="${STD_SHELL_LIB:-"${MY_DIRECTORY}/lib"}"
DOCKER_HELPER_DIRECTORY="${LIB_DIRECTORY}/docker"
readonly MY_DIRECTORY LIB_DIRECTORY DOCKER_HELPER_DIRECTORY

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
    echo "ERROR:  Failed to import shell helpers!" >&2
    exit 2
fi

# Pass control to the docker helper script
exec "${DOCKER_HELPER_DIRECTORY}/compose-start.sh" "$@"
```

Example `stop.sh`:

```bash
#!/usr/bin/env bash
################################################################################
# Stop the stack using the standard shell script library.
#
# Pass a `--help` flag to this script to get comprehensive documentation.
################################################################################
# Constants
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIRECTORY="${STD_SHELL_LIB:-"${MY_DIRECTORY}/lib"}"
DOCKER_HELPER_DIRECTORY="${LIB_DIRECTORY}/docker"
readonly MY_DIRECTORY LIB_DIRECTORY DOCKER_HELPER_DIRECTORY

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
    echo "ERROR:  Failed to import shell helpers!" >&2
    exit 2
fi

# Pass control to the docker helper script
exec "${DOCKER_HELPER_DIRECTORY}/compose-stop.sh" "$@"
```

## Quick Usage

Remember that you can pass `--help` to any of these scripts to get detailed
documentation, enabling more advanced use-cases.

* Build images for development (the default):  `./build.sh`
* Fresh build the image(s) for development and start the stack:
  `./build.sh --clean --start`
* Seperately "up" the stack:  `./start.sh`
* Check logs:  `./compose.sh logs`
* Read and follow the logs:  `./compose.sh logs -f`
* "Down" the stack (preserve artifacts):  `./stop.sh`
* Destroy the stack and clean up artifacts:  `./stop.sh --clean`
* Deploy the stack without using Docker Hub or any private image repository:
  `./deploy.sh host-1 host-2 host-N`

## Advanced Topics

1. When using Docker Secrets, deployment requires an additional script to help
   repair the secret file paths which Docker Compose will corrupt during the
   build.  Create an additional shell script in the top-level directory of your
   project:  `deploy-pre.sh`

```bash
#!/bin/bash
################################################################################
# Fix broken secrets because `docker compose config` output hard-codes their
# paths to the source machine's directory structure, which is non-portable.
################################################################################
# Constants
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIRECTORY="${STD_SHELL_LIB:-"${MY_DIRECTORY}/lib"}"
readonly MY_DIRECTORY LIB_DIRECTORY

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
    echo "ERROR:  Failed to import shell helpers!" >&2
    exit 2
fi

# Accept command-line arguments
_deploymentStage=${1:?"ERROR:  DEPLOYMENT_STAGE must be the first command-line argument!"}
_bakedComposeFile=${2:?"ERROR:  DOCKER_COMPOSE_FILE must be the second command-line argument!"}

# Write the original secrets to the baked Docker Compose file
yaml-merge \
        --nostdin \
        --array unique \
        docker/docker-compose.yaml \
        docker/docker-compose.${_deploymentStage}.yaml \
    | yaml-get --query=/secrets \
    | yaml-merge \
        --overwrite "$_bakedComposeFile" \
        --mergeat /secrets \
        --nostdin \
        "$_bakedComposeFile" \
        -
```
