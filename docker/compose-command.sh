#!/bin/bash
###############################################################################
# Run docker compose with an arbitrary command against baked configuration.
#
# Copyright 2025 William W. Kimball, Jr. MBA MSIS
# All rights reserved.
###############################################################################
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
	logError "Failed to import shell helpers!" >&2
	exit 2
fi

# Process command-line arguments, if there are any
_hasErrors=false
_deployStage=$DEPLOY_STAGE_DEVELOPMENT
_showMyOutput=true
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
$0 [OPTIONS] [--] COMMAND [ARGS]

Runs an arbitrary Docker Compose command against this project.  OPTIONS include:
  -d DEPLOY_STAGE, --stage DEPLOY_STAGE
       Indicate which run mode to use.  Must be one of:
         * ${DEPLOY_STAGE_DEVELOPMENT}
         * ${DEPLOY_STAGE_LAB}
         * ${DEPLOY_STAGE_STAGING}
         * ${DEPLOY_STAGE_PRODUCTION}
       The default is ${_deployStage}.  This controls which Docker Compose
       override file is used based on the presence of the DEPLOY_STAGE string
       within the file name matching the pattern:  docker-compose.*.yaml.
  -h, --help
       Display this help message and exit.
  -q, --quiet
       Suppress normal output from this script while allowing all COMMAND output
       to reach STDOUT and STDERR.  Error messages from this script are still
       printed to STDERR.
  -v, --version
       Display the version of this script and exit.
  --
       Separates the options from the command to run against the baked
       Docker Compose configuration.  This is necessary when the command
       starts with a hyphen (-), say when you wish to pass additional options
       to docker compose before the first command word.

  COMMAND [ARGS]
	   The command to run against the baked Docker Compose configuration.

EOHELP
			exit 0
			;;

		-q|--quiet)
			_showMyOutput=false
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
	echo "ERROR:  Docker is not running!" >&2
	_hasErrors=true
fi

# Verify Docker Compose is installed
if ! docker compose --version >/dev/null 2>&1; then
	echo "ERROR:  Docker Compose is not installed!" >&2
	_hasErrors=true
fi

# Bail if any errors have been detected
if $_hasErrors; then
	exit 1
fi

if $_showMyOutput; then
	logLine "Running '$@' against the ${_deployStage} environment..."
fi

# Bake the Docker Compose configuration file only if it is not already baked
# or not for the current run mode.
bakedComposeFile=
if isBakedComposeFile "$COMPOSE_BASE_FILE" "$_deployStage"; then
	if $_showMyOutput; then
		logLine "Using ${COMPOSE_BASE_FILE} as a pre-baked ${_deployStage} configuration."
	fi
	bakedComposeFile="$COMPOSE_BASE_FILE"
else
	# Identify the Docker Compose override file to use
	overrideComposeFile="${DOCKER_DIRECTORY}/docker-compose.${_deployStage}.yaml"
	if [ ! -f "$overrideComposeFile" ]; then
		overrideComposeFile=
	fi

	# Create a temporary file to hold the baked Docker Compose configuration
	# file.  Ensure it is destroyed when the script exits.
	bakedComposeFile=$(mktemp)
	trap "rm -f $bakedComposeFile" EXIT

	dynamicBakeComposeFile "$bakedComposeFile" "$_deployStage" "$DOCKER_DIRECTORY"
	if [ 0 -ne $? ]; then
		noBakeErrorMessage="Unable to bake ${COMPOSE_BASE_FILE}"
		if [ -n "$overrideComposeFile" ]; then
			noBakeErrorMessage+=" with ${overrideComposeFile}"
		fi
		noBakeErrorMessage+="!"
		logError "$noBakeErrorMessage"
		exit 3
	fi
fi

if $_showMyOutput; then
	echo
fi

# Run the command against the baked Docker Compose configuration
dockerCompose "$bakedComposeFile" "" \
	--profile "${_deployStage}" \
	"$@"
