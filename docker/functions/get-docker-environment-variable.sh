################################################################################
# Implement the getDockerEnvironmentVariable function.
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
# Get the value of a named environment variable from any possible Docker source.
#
# This function searches for the specified environment variable in the following
# locations, in preferred order:
# 1. Environment variables of the current shell
# 2. Any available Docker Compose YAML files in the specified directory,
#    filtered by the deployment stage
# 3. .env* files in the specified directory, filtered by the deployment stage
#
# Arguments:
# @param string $1 Name of the environment variable to resolve; this value is
#                  case-sensitive.
# @param string $2 Either a pre-baked Docker Compose YAML configuration file or
#                  a directory where the Docker Compose YAML and .env files can
#                  be found.
# @param string $3 Name of the deployment stage.  Used to disambiguate between
#                  files like docker-compose.staging.yaml versus
#                  docker-compose.production.yaml, .env.staging versus
#                  .env.production, and so on.  Note that docker-compose.yaml
#                  and .env are always read when either exists.
#
# @return integer One of:
#   0 on success
#   1 when any required argument are empty or null
#   2 when no Docker Compose YAML or .env* files could be found
#   3 when the environment variable could not be resolved
# STDOUT:  The resolved value of the environment variable on success
# STDERR:  An error message on failure
#
# @example With a Docker Compose file
#   getDockerEnvironmentVariable "MY_ENV_VAR" "docker/docker-compose.yaml"
#
# @example Without a Docker Compose file
#   getDockerEnvironmentVariable "MY_ENV_VAR"
##
function getDockerEnvironmentVariable {
	local varName=${1:?"ERROR:  A Docker environment variable name must be provided as the first positional argument to ${FUNCNAME[0]}"}
	local dockerRef=${2:?"ERROR:  Either a pre-baked Docker Compose YAML file or a directory containing Docker Compose confugraiton files must be provided as the second positional argument to ${FUNCNAME[0]}"}
	local deploymentStage=${3:?"ERROR:  The deployment stage must be provided as the third positional argument to ${FUNCNAME[0]}"}
	local dockerDir hasBakedComposeFile tempBakedFile possibleValue returnState=0

    # Validate varName is a valid shell environment variable identifier
	if ! [[ "$varName" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
		logError "Invalid environment variable name:  ${varName}"
		return 1
	fi

	# First, identify the Docker directory based on whether dockerRef is a file
	# or a directory.  Allow symbolic links.
	hasBakedComposeFile=false
	if [ -f "$dockerRef" ]; then
		dockerDir="$(dirname "$dockerRef")"
		hasBakedComposeFile=true
	elif [ -d "$dockerRef" ]; then
		dockerDir="$dockerRef"
	elif [ -L "$dockerRef" ]; then
		# The readlink command must be available
		if ! command -v readlink &>/dev/null; then
			logError "The readlink command must be available to resolve symbolic link:  $dockerRef"
			return 1
		fi

		# Resolve the symbolic link to get the actual file or directory
		dockerDir="$(dirname "$(readlink -f "$dockerRef")")"
	else
		logError "Invalid Docker reference:  $dockerRef"
		return 1
	fi

	# Then, check the shell environment
	if [ -n "${!varName}" ]; then
		echo "${!varName}"
		return 0
	fi

	# Next, check the Docker Compose YAML file(s)
	if $hasBakedComposeFile; then
		# Check for the variable within the baked Docker Compose file
		possibleValue=$(yaml-get --query="(/services/**/environment/${varName})[0]" "$dockerRef" 2>/dev/null)
		if [ 0 -eq $? ] && [ -n "$possibleValue" ]; then
			echo "$possibleValue"
			return 0
		fi
	else
		# Bake and search the Docker Compose file(s)
		tempBakedFile=$(mktemp)
		if dynamicBakeComposeFile "$tempBakedFile" "$deploymentStage" "$dockerDir"
		then
			# Check for the variable within the baked Docker Compose file
			possibleValue=$(yaml-get --query="(/services/**/environment/${varName})[0]" "$tempBakedFile" 2>/dev/null)
			if [ 0 -eq $? ] && [ -n "$possibleValue" ]; then
				echo "$possibleValue"
				rm -f "$tempBakedFile"
				return 0
			fi
		else
			returnState=$?
			if [ "$returnState" -eq 2 ]; then
				logError "No Docker Compose YAML files found in ${dockerDir}."
			else
				logError "Failed to bake the Docker Compose file:  $tempBakedFile"
			fi
			rm -f "$tempBakedFile"
			return 2
		fi
	fi

	# Finally, check for the value in any available .env files
	tempBakedFile=$(mktemp)
	if dynamicMergeEnvFiles "$tempBakedFile" "$dockerDir" "$deploymentStage"
	then
		# Check for the variable within the merged .env file
		possibleValue=$(grep -E "^${varName}=" "$tempBakedFile" | cut -d'=' -f2- | sort -u)
		if [ -n "$possibleValue" ]; then
			echo "$possibleValue"
			rm -f "$tempBakedFile"
			return 0
		fi
	else
		returnState=$?
		if [ "$returnState" -eq 1 ]; then
			logWarning "No .env files found in ${dockerDir}."
		else
			logError "Failed to merge environment files"
		fi
		rm -f "$tempBakedFile"
		return 2
	fi

	return 3
}
