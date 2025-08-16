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
	local envFile envVars envVar returnCode
	declare -a envFiles
	shift 2

	# Discover all relevant environment files
	if ! discoverEnvFiles envFiles "$dockerDir" "$deploymentStage" "$@"; then
		returnCode=$?
		if [ "$returnCode" -eq 1 ]; then
			logWarning "No environment files found to source."
		fi
		return $returnCode
	fi

	# Attempt to source all discovered environment variable files
	returnCode=1
	for envFile in "${envFiles[@]}"; do
		if [ -f "$envFile" ]; then
			# Indicate that at least one file has been found when, so far, none
			# have.
			if [ "$returnCode" -eq 1 ]; then
				returnCode=0
			fi

			logInfo "Sourcing environment variables from:  $envFile"

			# Get the list of (valid) environment variables defined in this file
			envVars=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$envFile" | cut -d'=' -f1 | sort -u)

			# Skip the file when the list is empty
			if [ -z "$envVars" ]; then
				logWarning "No valid environment variables found in:  $envFile"
				continue
			fi

			if ! source "$envFile"; then
				logError "Failed to source environment variables from:  $envFile"
				returnCode=2
				continue
			fi

			# Log the variable names as a list
			logDebug "Exporting non-empty environment variables from $envFile:"
			for envVar in $envVars; do
				logDebug "  - $envVar"
			done

			# Export all variables that were defined in the environment file
			for envVar in $envVars; do
				if [[ -n "${!envVar}" ]]; then
					export "$envVar"
					logDebug "Exported environment variable:  ${envVar}=${!envVar}"
				fi
			done
		else
			logWarning "Environment variable file not found:  $envFile"
		fi
	done

	return $returnCode
}
