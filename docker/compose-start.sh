#!/bin/bash
###############################################################################
# Start the Docker Compose stack for a given deployment stage.
#
# External control variables:
# TMPDIR <string> The directory in which to create temporary files like baked
#                 Docker Compose files.  The default is the system's temporary
#                 directory.
#
# Optional external assets:
# - start-pre.sh <DEPLOYMENT_STAGE> <BAKED_DOCKER_COMPOSE_FILE>
#   A script to run before starting the environment.  This script is run in the
#   context of this parent script, so it will receive a local copy of all of the
#   variables and functions defined in this script; changing them will have no
#   effect on this parent script.  However, it can be used to manipulate the
#   baked Docker Compose file before it is used.  The script file must be in the
#   project directory -- two directory levels higher than the directory
#   containing this parent script -- and must be executable by the same user who
#   is running this parent script.  The most common use-cases for this script
#   are to validate the baked Docker Compose file (check for mandatory
#   environment variables, etc.) or to modify the baked Docker Compose file
#   pursuant to deployment requirements (e.g., to securely and temporarily set
#   the database credentials).
# - start-post.sh <DEPLOYMENT_STAGE> <BAKED_DOCKER_COMPOSE_FILE>
#   A script to run after starting the environment.  This script is run in the
#   context of this parent script, so it will receive a local copy of all of the
#   variables and functions defined in this script; changing them will have no
#   effect on this parent script.  This is run after the environment is started
#   so any changes made to the baked Docker Compose file will be moot.  The
#   script file must be in the project directory -- two directory levels higher
#   than the directory containing this parent script -- and must be executable
#   by the same user who is running this parent script.  The most common
#   use-cases for this script are to force a wait for the primary service to
#   become responsive, to run a database migration process, or to run
#   application-specific initialization scripts within the running container.
#
# Copyright 2025 William W. Kimball, Jr. MBA MSIS
# All rights reserved.
###############################################################################
# Constants
MY_VERSION='2025.04.18-1'
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIRECTORY="$(cd "${MY_DIRECTORY}/../../" && pwd)"
LIB_DIRECTORY="${PROJECT_DIRECTORY}/lib"
DOCKER_DIRECTORY="${PROJECT_DIRECTORY}/docker"
COMPOSE_BASE_FILE="${DOCKER_DIRECTORY}/docker-compose.yaml"
DEPLOY_STAGE_DEVELOPMENT=development
DEPLOY_STAGE_LAB=lab
DEPLOY_STAGE_QA=qa
DEPLOY_STAGE_STAGING=staging
DEPLOY_STAGE_PRODUCTION=production
readonly MY_VERSION MY_DIRECTORY PROJECT_DIRECTORY LIB_DIRECTORY \
	DOCKER_DIRECTORY COMPOSE_BASE_FILE DEPLOY_STAGE_DEVELOPMENT \
	DEPLOY_STAGE_LAB DEPLOY_STAGE_QA DEPLOY_STAGE_STAGING \
	DEPLOY_STAGE_PRODUCTION

# Switch to the project directory to resolve relative paths
cd "${PROJECT_DIRECTORY}"

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
	echo "ERROR:  Failed to import shell helpers!" >&2
	exit 2
fi

# Process command-line arguments, if there are any
_hasErrors=false
_deployStage=$DEPLOY_STAGE_DEVELOPMENT
_tailLogs=false
while [ $# -gt 0 ]; do
	case $1 in
		-d|--stage)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				if [[ "$2" =~ ^[Dd] ]]; then
					_deployStage=$DEPLOY_STAGE_DEVELOPMENT
					_pushImages=false
				elif [[ "$2" =~ ^[Ll] ]]; then
					_deployStage=$DEPLOY_STAGE_LAB
				elif [[ "$2" =~ ^[Qq] ]]; then
					_deployStage=$DEPLOY_STAGE_QA
				elif [[ "$2" =~ ^[Ss] ]]; then
					_deployStage=$DEPLOY_STAGE_STAGING
				elif [[ "$2" =~ ^[Pp] ]]; then
					_deployStage=$DEPLOY_STAGE_PRODUCTION
				else
					logError "Unsupported value, ${2}, for $1 option."
					_hasErrors=true
				fi
				shift
			fi
			;;

		-h|--help)
			cat <<EOHELP
$0 [OPTIONS]

Starts the service(s) of this project.  OPTIONS include:
  -h, --help
       Display this help message and exit.
  -d DEPLOY_STAGE, --stage DEPLOY_STAGE
       Indicate which run mode to use.  Must be one of:
         * ${DEPLOY_STAGE_DEVELOPMENT}
         * ${DEPLOY_STAGE_LAB}
         * ${DEPLOY_STAGE_STAGING}
         * ${DEPLOY_STAGE_PRODUCTION}
       The default is ${_deployStage}.  This controls which Docker Compose
       override file is used based on the presence of the DEPLOY_STAGE string
       within the file name matching the pattern:  docker-compose.*.yaml.
  -t, --tail
       Tail the Docker Compose logs after starting.
  -v, --version
       Display the version of this script and exit.

EOHELP
			exit 0
			;;

		-t|--tail)
			_tailLogs=true
			;;

		-v|--version)
			logLine "$0 ${MY_VERSION}"
			exit 0
			;;

		--)
			shift
			break
			;;

		-*)
			logError "Unknown option:  $1"
			_hasErrors=true
			;;

		*)
			break
			;;
	esac

	shift
done

# Verify Docker is running
if ! docker info >/dev/null 2>&1; then
	logError "Docker is not running!"
	_hasErrors=true
fi

# Verify Docker Compose is installed
if ! docker compose --version >/dev/null 2>&1; then
	logError "Docker Compose is not installed!"
	_hasErrors=true
fi

# yamlpath (and Python 3) is required to parse various files
if ! yaml-get --version >/dev/null 2>&1; then
	logError "yamlpath (https://github.com/wwkimball/yamlpath?tab=readme-ov-file#installing) is not installed!"
	_hasErrors=true
fi

# Bake the Docker Compose configuration file only if it is not already baked
# or not for the current run mode.
bakedComposeFile=
if isBakedComposeFile "$COMPOSE_BASE_FILE" "$_deployStage"; then
	logLine "Using ${COMPOSE_BASE_FILE} as a pre-baked ${_deployStage} configuration."
	bakedComposeFile="$COMPOSE_BASE_FILE"
else
	# Identify the Docker Compose override file to use
	overrideComposeFile="${DOCKER_DIRECTORY}"/docker-compose.${_deployStage}.yaml
	if [ ! -f "$overrideComposeFile" ]; then
		overrideComposeFile=
	fi

	# Create a temporary file to hold the baked Docker Compose configuration
	# file.  Ensure it is destroyed when the script exits.
	bakedComposeFile=$(mktemp)
	trap "rm -f $bakedComposeFile" EXIT

	# Bake the Docker Compose configuration file
	dynamicBakeComposeFile "$bakedComposeFile" "$_deployStage" "$DOCKER_DIRECTORY"
	if [ 0 -ne $? ]; then
		_hasErrors=true
		noBakeErrorMessage="Unable to bake ${COMPOSE_BASE_FILE}"
		if [ -n "$overrideComposeFile" ]; then
			noBakeErrorMessage+=" with ${overrideComposeFile}"
		fi
		noBakeErrorMessage+="!"
		logError "$noBakeErrorMessage"
	else
		# Remove all build contexts from the baked configuration
		logInfo "Removing build contexts from the baked Docker Compose configuration file..."
		yaml-set --nostdin --delete --change='**.build' "$bakedComposeFile" 2>/dev/null
	fi
fi

# Bail if any errors have been detected
if $_hasErrors; then
	exit 1
fi

echo "Starting the ${_deployStage} environment..."

# Run the pre-start script, if it exists
startPreScript="${PROJECT_DIRECTORY}/start-pre.sh"
logLine "Checking for pre-start script, ${startPreScript}..."
if [ -f "$startPreScript" ]; then
	if [ -x "$startPreScript" ]; then
		logInfo "Running discovered script, ${startPreScript}..."
		if ! "$startPreScript" "$_deployStage" "$bakedComposeFile"
		then
			logError "Pre-start script, ${startPreScript}, failed!"
			exit 3
		fi
	else
		errorOut 4 "Pre-start script, ${startPreScript}, is not executable!"
	fi
fi

# Start the environment
if ! dockerCompose "$bakedComposeFile" "" \
		--profile "$_deployStage" up --detach \
		--wait --remove-orphans
then
	errorOut 5 "Failed to start the environment!"
fi

# Run the post-start script, if it exists
startPostScript="${PROJECT_DIRECTORY}/start-post.sh"
logLine "Checking for post-start script, ${startPostScript}..."
if [ -f "$startPostScript" ]; then
	if [ -x "$startPostScript" ]; then
		logInfo "Running discovered script, ${startPostScript}..."
		if ! "$startPostScript" "$_deployStage" "$bakedComposeFile"
		then
			logWarning "Post-start script, ${startPostScript}, failed!"
		fi
	else
		logWarning "Post-start script, ${startPostScript}, is not executable; skipping."
	fi
fi

logLine "\nThe environment is up and running.  To stop it, run:"
logLine "    ./stop.sh --stage ${_deployStage}"

if $_tailLogs; then
	logInfo "\nTailing the Docker Compose logs.  Press Ctrl+C to stop."
	dockerCompose "$bakedComposeFile" "" \
		logs --follow
fi
