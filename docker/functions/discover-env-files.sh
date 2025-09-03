################################################################################
# Implement the discoverEnvFiles function.
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# Dynamically load the common logging functions
if [ -z "$LIB_DIRECTORY" ]; then
	# The common library directory is not set, so set it to the default value
	MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	PROJECT_DIRECTORY="$(cd "${MY_DIRECTORY}/../../../" && pwd)"
	LIB_DIRECTORY="${PROJECT_DIRECTORY}/lib"
	readonly MY_DIRECTORY PROJECT_DIRECTORY LIB_DIRECTORY
fi
setLoggerSource="${LIB_DIRECTORY}/logging/set-logger.sh"
if ! source "$setLoggerSource"; then
	echo "ERROR:  Unable to source ${setLoggerSource}!" >&2
	exit 2
fi
unset setLoggerSource

###
# Discover all relevant Docker environment variable files.
#
# All environment files in the given Docker directory will be discovered which
# share the same deployment stage suffix.  Any pertinent docker-compose.*.yaml
# files will be evaluated to find all relevant service names to further inform
# the selection of environment files.
#
# MAINTENANCE NOTE:
# This function is deeply embedded in various scripts and other functions.  Its
# output controls key behaviors of Docker Compose and related tooling.  Any
# spurious content sent to STDOUT by this function can cause issues that are
# extremely difficult to diagnose.  As such, all non-value output MUST be sent
# to STDERR.  Only empty strings (nothing found) or actual discovered values
# should be sent to STDOUT.
#
# @param string $1 The Docker directory to inspect for environment variable
#                  files
# @param string $2 The deployment stage name, i.e.:  development, lab, qa,
#                  staging, and production.
# @param string $@ Additional, specific environment variable files to discover.
#                  When the files are already in the Docker directory, you do
#                  not need to fully-qualify these file paths.
#
# @return integer One of:
#   0 on success
#   1 when no environment files were found
#   3 when there is an error attempting to handle the Docker Compose file(s)
#
# @example
#   declare -a envFiles
#   discoverEnvFiles envFiles "/path/to/docker/files" "development" ".env.custom"
##
function discoverEnvFiles() {
	local -n envFilesRef=$1
	local dockerDir=${2:?"ERROR:  The Docker files directory must be provided as the second positional argument to ${FUNCNAME[0]}"}
	local deploymentStage=${3:?"ERROR:  The deployment stage must be provided as the third positional argument to ${FUNCNAME[0]}"}
	local envFile mergedComposeFile serviceNames evalFile="" returnCode=1
	local lcDeploymentStage=${deploymentStage,,}
	shift 3

	# Track the environment variable files to discover
	envFilesRef=()
	evalFile="${dockerDir}/.env"
	if [ -f "$evalFile" ]; then
		envFilesRef+=("$evalFile")
	fi
	evalFile="${dockerDir}/.env.${lcDeploymentStage}"
	if [ -f "$evalFile" ]; then
		envFilesRef+=("$evalFile")
	fi

	# Because environment variables are often used in the Docker Compose YAML
	# files, Docker Compose often errors out when they haven't yet been sourced
	# before attempting to use them.  As such, we cannot rely on Docker Compose
	# to merge these files automatically.  So, we will use the yaml-merge
	# command, which does not depend on environment variables to merge YAML
	# content.  First, identify the base docker-compose.yaml (or .yml) file and
	# whether a deployment stage override is also available.
	local baseFileName=docker-compose.yaml
	local overrideFileName="docker-compose.${lcDeploymentStage}.yaml"
	local composeFileTally=0
	declare -a mergeArgs=(--nostdin)

	# Use a temp file for the merge results
	mergedComposeFile=$(mktemp)
	mergeArgs+=(--overwrite)
	mergeArgs+=("$mergedComposeFile")

	if [ ! -f "${dockerDir}/${baseFileName}" ]; then
		baseFileName=docker-compose.yml
	fi
	if [ -f "${dockerDir}/${baseFileName}" ]; then
		((composeFileTally++))
		evalFile="${dockerDir}/${baseFileName}"
		mergeArgs+=("$evalFile")
	fi
	if [ ! -f "${dockerDir}/${overrideFileName}" ]; then
		overrideFileName="docker-compose.${lcDeploymentStage}.yml"
	fi
	if [ -f "${dockerDir}/${overrideFileName}" ]; then
		((composeFileTally++))
		evalFile="${dockerDir}/${overrideFileName}"
		mergeArgs+=("$evalFile")
	fi

	# Merge only when there is more than one compose file
	local hasComposeFiles=false
	case "$composeFileTally" in
		0)	logWarningToError "No Docker Compose files found." ;;

		1)	hasComposeFiles=true
			if ! cp "$evalFile" "$mergedComposeFile"; then
				logError "Failed to copy ${evalFile} to ${mergedComposeFile}"
				return 3
			fi
		;;

		2)	hasComposeFiles=true
			if ! yaml-merge "${mergeArgs[@]}" &>/dev/null; then
				logError "Failed to merge Docker Compose files"
				return 3
			fi
		;;
	esac

	# Extract service names from the merged Docker Compose file and look for
	# environment variable files matching those names.
	serviceNames=$(yaml-get --query='services.*[name()]' "$mergedComposeFile" 2>/dev/null)
	for serviceName in $serviceNames; do
		evalFile="${dockerDir}/.env.${serviceName}"
		if [ -f "$evalFile" ]; then
			envFilesRef+=("$evalFile")
		fi
		evalFile="${dockerDir}/.env.${serviceName}.${lcDeploymentStage}"
		if [ -f "$evalFile" ]; then
			envFilesRef+=("$evalFile")
		fi
	done

	# Any remaining arguments are presumed to be relative environment
	# variable files, which will override anything that will have been discovered
	# up to this point.
	for envFile in "$@"; do
		# When there are no path seperators in the value, prepend the Docker
		# directory to the value.
		if [[ "$envFile" != /* ]]; then
			envFile="${dockerDir}/${envFile}"
		fi

		if [ -f "$envFile" ]; then
			envFilesRef+=("$envFile")
		else
			logWarningToError "Environment variable file not found:  $envFile"
		fi
	done

	# Check if any files were actually found
	for envFile in "${envFilesRef[@]}"; do
		if [ -f "$envFile" ]; then
			returnCode=0
			break
		fi
	done

	# Destroy the temp file should it still exist
	if [ -f "$mergedComposeFile" ]; then
		rm -f "$mergedComposeFile"
	fi

	return $returnCode
}
