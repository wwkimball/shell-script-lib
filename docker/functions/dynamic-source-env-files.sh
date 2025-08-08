################################################################################
# Implement the dynamicSourceEnvFiles function.
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
# Dynamically source all relevant Docker environment variable files.
#
# All environment files in the given Docker directory will be sourced which
# share the same deployment stage suffix.  Any pertinent docker-compose.*.yaml
# files will be evaluated to find all relevant service names to further inform
# the selection of environment files.
#
# @param string $1 The Docker directory to inspect for environment variable
#                  files
# @param string $2 The deployment stage name, i.e.:  development, lab, qa,
#                  staging, and production.
# @param string $@ Additional, specific environment variable files to source.
#                  When the files are already in the Docker directory, you do
#                  not need to fully-qualify these file paths.
#
# @return integer One of:
#   0 on success
#   1 when no environment files were found
#   2 when sourcing environment files failed
#   3 when there is an error attempting to handle the Docker Compose file(s)
#
# @example
#   dynamicSourceEnvFiles "/path/to/docker/files" "development" ".env.custom"
##
function dynamicSourceEnvFiles() {
	local dockerDir=${1:?"ERROR:  The Docker files directory must be provided as the first positional argument to ${FUNCNAME[0]}"}
	local deploymentStage=${2:?"ERROR:  The deployment stage must be provided as the second positional argument to ${FUNCNAME[0]}"}
	local envFile envFiles mergedComposeFile serviceNames returnCode=1
	shift 2

	# Track the environment variable files to source
	declare -a envFiles=(
		"${dockerDir}/.env"
		"${dockerDir}/.env.${deploymentStage}"
	)

	# Because environment variables are often used in the Docker Compose YAML
	# files, Docker Compose often errors out when they haven't yet been sourced
	# before attempting to use them.  As such, we cannot rely on Docker Compose
	# to merge these files automatically.  So, we will use the yaml-merge
	# command, which does not depend on environment variables to merge YAML
	# content.  First, identify the base docker-compose.yaml (or .yml) file and
	# whether a deployment stage override is also available.
	local baseFileName=docker-compose.yaml
	local overrideFileName="docker-compose.${deploymentStage}.yaml"
	local soleComposeFile=""
	local composeFileTally=0
	declare -a mergeArgs=(--no-stdin)

	# Use a temp file for the merge results
	mergedComposeFile=$(mktemp)
	mergeArgs+=(--overwrite)
	mergeArgs+=("$mergedComposeFile")

	if [ ! -f "${dockerDir}/${baseFileName}" ]; then
		baseFileName=docker-compose.yml
	fi
	if [ -f "${dockerDir}/${baseFileName}" ]; then
		((composeFileTally++))
		soleComposeFile="${dockerDir}/${baseFileName}"
		mergeArgs+=("$soleComposeFile")
	fi
	if [ ! -f "${dockerDir}/${overrideFileName}" ]; then
		overrideFileName="docker-compose.${deploymentStage}.yml"
	fi
	if [ -f "${dockerDir}/${overrideFileName}" ]; then
		((composeFileTally++))
		soleComposeFile="${dockerDir}/${overrideFileName}"
		mergeArgs+=("$soleComposeFile")
	fi

	# Merge only when there is more than one compose file
	local hasComposeFiles=false
	case "$composeFileTally" in
		0)	logWarning "No Docker Compose files found." ;;

		1)	hasComposeFiles=true
			if ! cp "$soleComposeFile" "$mergedComposeFile"; then
				logError "Failed to copy ${soleComposeFile} to ${mergedComposeFile}"
				return 3
			fi
		;;

		2)	hasComposeFiles=true
			yaml-merge "${mergeArgs[@]}"
		;;
	esac

	# Extract service names from the merged Docker Compose file and look for
	# environment variable files matching those names.
	serviceNames=$(yaml-get --query='services.*[name()]' "$mergedComposeFile" 2>/dev/null)
	for serviceName in $serviceNames; do
		soleComposeFile="${dockerDir}/.env.${serviceName}"
		if [ -f "$soleComposeFile" ]; then
			envFiles+=("$soleComposeFile")
		fi
		soleComposeFile="${dockerDir}/.env.${serviceName}.${deploymentStage}"
		if [ -f "$soleComposeFile" ]; then
			envFiles+=("$soleComposeFile")
		fi
	done

	# Any remaining arguments are presumed to be relative environment
	# variable files, which will override anything that will have been sourced
	# up to this point.
	for envFile in "$@"; do
		# When there are no path seperators in the value, prepend the Docker
		# directory to the value.
		if [[ "$envFile" != /* ]]; then
			envFile="${dockerDir}/${envFile}"
		fi

		if [ -f "$envFile" ]; then
			envFiles+=("$envFile")
		else
			logWarning "Environment variable file not found:  $envFile"
		fi
	done

	# Attempt to source all discovered environment variable files
	for envFile in "${envFiles[@]}"; do
		if [ -f "$envFile" ]; then
			# Indicate that at least one file has been found when, so far, none
			# have.
			if [ "$returnCode" -eq 1 ]; then
				returnCode=0
			fi

			logInfo "Sourcing environment variables from:  $envFile"
			if ! source "$envFile"; then
				logError "Failed to source environment variables from:  $envFile"
				returnCode=2
			fi
		else
			logWarning "Environment variable file not found:  $envFile"
		fi
	done

	# Destroy the temp file should it still exist
	if [ -f "$mergedComposeFile" ]; then
		rm -f "$mergedComposeFile"
	fi

	return $returnCode
}
