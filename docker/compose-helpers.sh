###############################################################################
# Define shell helper functions for use with Docker Compose.
###############################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

###
# Run the docker compose command with the base and optional override file.
#
# @param string $1 The base Docker Compose file.
# @param string $2 The optional override Docker Compose file.
# @param string $@ The remaining arguments to Docker Compose.
#
# @return integer The exit code from Docker Compose.
##
function dockerCompose() {
	local mainComposeFile envComposeFile
	mainComposeFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file."}
	envComposeFile=$2
	shift 2

	if [ ! -z "$envComposeFile" -a -f "$envComposeFile" ]; then
		docker compose -f "$mainComposeFile" -f "$envComposeFile" "$@"
	else
		docker compose -f "$mainComposeFile" "$@"
	fi
}

###
# Define a function which waits for a named Docker Compose service to be ready.
#
# @param string $1 The profile name; one of development, lab, qa, staging, or
#                  production.
# @param string $2 The name of the service to wait for.
# @param string $3 The base Docker Compose file.
# @param string $4 The optional override Docker Compose file.
# @param string $5 The command to run in the service to check for readiness.
# @param string $6 The string to check for in the output of the command.
# @param integer $7 The maximum number of seconds to wait for the service.
# @param integer $8 The maximum number of errors to allow before giving up.
#
# @return integer 0 if the service became ready, 1 if it timed out, or 2 if it
#                 failed too many times.
##
function awaitService() {
	local profileName serviceName mainComposeFile envComposeFile readyCommand \
		readyCheck maximumWaitSeconds maximumErrors tempFile waitedSeconds \
		seenErrors returnState
	profileName=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing profile name."}
	serviceName=${2:?"ERROR:  ${FUNCNAME[0]}:  Missing service name."}
	mainComposeFile=${3:?"ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file."}
	envComposeFile=$4
	readyCommand=${5:-"echo 'ready'"}
	readyCheck=${6:-"ready"}
	maximumWaitSeconds=${7:-10}
	maximumErrors=${8:-5}

	# Use a temp file to check for errors from the service
	tempFile=$(mktemp)
	waitedSeconds=0
	seenErrors=0
	returnState=0
	trap "rm -f '$tempFile'" EXIT

	echo
	echo "Waiting for ${serviceName} to become ready..."
	while ! dockerCompose "$mainComposeFile" "$envComposeFile" \
		--profile "$profileName" \
		exec "$serviceName" \
		sh -c "$readyCommand" \
		2>&1 | tee "$tempFile" | grep -q "$readyCheck"
	do
		echo -n "   ${waitedSeconds}(${PIPESTATUS[0]},${PIPESTATUS[2]}):  "
		cat "$tempFile"

		# Check for service "${serviceName}" is not running
		if grep -q "service \"${serviceName}\" is not running" "$tempFile"; then
			seenErrors=$((seenErrors + 1))
		fi

		sleep 1
		waitedSeconds=$((waitedSeconds + 1))

		# Check for timeout
		if [ $waitedSeconds -ge $maximumWaitSeconds ]; then
			returnState=1
			echo
			echo "ERROR:  ${serviceName} did not become ready within ${maximumWaitSeconds} seconds!" >&2
			break
		fi

		# Check for too many errors
		if [ $seenErrors -ge $maximumErrors ]; then
			returnState=2
			echo
			echo "ERROR:  ${serviceName} has failed too many times!" >&2
			break
		fi
	done
	echo -n "   ${waitedSeconds}(${PIPESTATUS[0]},${PIPESTATUS[2]}):  "
	cat "$tempFile"
	echo

	rm -f "$tempFile"
	return $returnState
}

###
# Start the environment and wait for a named service to be ready.
#
# @param string $1 The profile name; one of development, lab, qa, staging, or
#                  production.
# @param string $2 The name of the service to wait for.
# @param string $3 The base Docker Compose file.
# @param string $4 The optional override Docker Compose file.
# @param string $5 The command to run in the service to check for readiness.
# @param string $6 The string to check for in the output of the command.
# @param integer $7 The maximum number of seconds to wait for the service.
# @param integer $8 The maximum number of errors to allow before giving up.
#
# @return integer 0 if the service became ready, 1 if it timed out, or 2 if it
#                 failed too many times.
##
function startAndAwaitService() {
	local profileName serviceName mainComposeFile envComposeFile readyCommand \
		readyCheck maximumWaitSeconds maximumErrors
	profileName=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing profile name."}
	serviceName=${2:?"ERROR:  ${FUNCNAME[0]}:  Missing service name."}
	mainComposeFile=${3:?"ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file."}
	envComposeFile=$4
	readyCommand=$5
	readyCheck=$6
	maximumWaitSeconds=$7
	maximumErrors=$8

	echo
	echo "Starting the ${profileName} environment..."
	dockerCompose "$mainComposeFile" "$envComposeFile" \
		--profile "$profileName" \
		up -d || return $?

	awaitService "$profileName" "$serviceName" \
		"$mainComposeFile" "$envComposeFile" \
		"$readyCommand" "$readyCheck" \
		"$maximumWaitSeconds" "$maximumErrors"
}

###
# Bake Docker Compose configuration files for a named profile.
#
# This creates a new Docker Compose file for the named profile by merging the
# base Docker Compose file with the optional override file, expanding all
# shell variables within them (from .env and any already-exported shell
# environment variables), and adding environment variables for the content of
# all env_file entries.  Remember that any .env and referenced env_file files
# must be present in or relative to the current directory.
#
# @param string $1 The output file to create with the baked configuration.
# @param string $2 The profile name; one of development, lab, qa, staging, or
#                  production.
# @param string $3 The base Docker Compose file.
# @param string $4 The optional override Docker Compose file.
#
# @return void
##
function bakeComposeFile() {
	local outputFile profileName mainComposeFile envComposeFile
	outputFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing output file name."}
	profileName=${2:?"ERROR:  ${FUNCNAME[0]}:  Missing profile name."}
	mainComposeFile=${3:?"ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file."}
	envComposeFile=$4

	dockerCompose "$mainComposeFile" "$envComposeFile" \
		--profile "$profileName" \
		config >"$outputFile"
}

###
# Bake Docker Compose configuration files for a named profile, dynamically.
#
# Similar to bakeComposeFile(), but this function dynamically identifies the
# base and override files based on a given source directory to look in along
# with an identifier to seek as part of the filenames.  This is useful for
# baking configuration files for a specific environment, such as "development"
# "production", and so on but without having to hard-code the filenames and
# independenty identify whether any/all of the files exist.
#
# The identifier will be sought by injecting it before the .yaml extension of
# the compose file, but after ".env" for the environment file.  The base
# compose file is always "docker-compose.yaml" and the base environment file is
# always ".env".  So, when the identifier is "development", the override
# compose file would be "docker-compose.development.yaml" and the override
# environment file would be ".env.development".
#
# @param string $1 The output file to create with the baked configuration.
# @param string $2 The profile name; one of development, lab, qa, staging,
#                  production, and so on.  This is also the identifier to seek
#				   in the filenames.  Defaults to "development".
# @param string $3 The source directory to look in for the base files.
#                  Defaults to "docker".
#
# @return integer 0 if the files were baked successfully, non-zero otherwise.
#
# @example
#   dynamicBakeComposeFile "my-baked-config.yaml"
#   dynamicBakeComposeFile "my-baked-config.yaml" "production"
#   dynamicBakeComposeFile "my-baked-config.yaml" "staging" "$(pwd)"
##
function dynamicBakeComposeFile() {
	local outputFile profileName sourceDirectory mainComposeFile \
		overrideComposeFile mainEnvFile overrideEnvFile tempEnvFile \
		altMainComposeFile altOverrideComposeFile returnState
	outputFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing output file name."}
	profileName=${2:-"development"}
	sourceDirectory=${3:-"docker"}
	mainComposeFile="${sourceDirectory}/docker-compose.yaml"
	overrideComposeFile="${sourceDirectory}/docker-compose.${profileName}.yaml"
	mainEnvFile="${sourceDirectory}/.env"
	overrideEnvFile="${sourceDirectory}/.env.${profileName}"
	returnState=0

	if [ ! -f "$mainComposeFile" ]; then
		# Allow for the incorrect ".yml" extension
		altMainComposeFile="${sourceDirectory}/docker-compose.yml"
		if [ -f "$altMainComposeFile" ]; then
			mainComposeFile="$altMainComposeFile"
		else
			echo "ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file:  ${mainComposeFile}" >&2
			return 2
		fi
	fi

	if [ ! -f "$overrideComposeFile" ]; then
		# Allow for the incorrect ".yml" extension
		altOverrideComposeFile="${sourceDirectory}/docker-compose.${profileName}.yml"
		if [ -f "$altOverrideComposeFile" ]; then
			overrideComposeFile="$altOverrideComposeFile"
		else
			overrideComposeFile=''
		fi
	fi

	if [ ! -f "$mainEnvFile" ]; then
		mainEnvFile=''
	fi

	if [ ! -f "$overrideEnvFile" ]; then
		overrideEnvFile=''
	fi

	# Either, neither, or both of the environment variable files may be
	# present.  Simplify the logic by creating a temporary file to hold the
	# environment variables to be used.
	tempEnvFile=$(mktemp)
	trap "rm -f '$tempEnvFile'" EXIT

	# Merge the environment variables from the base and override files
	echo "# Environment variables for ${profileName} environment" >"$tempEnvFile"
	if [ ! -z "$mainEnvFile" ]; then
		cat "$mainEnvFile" >>"$tempEnvFile"
	fi

	if [ ! -z "$overrideEnvFile" ]; then
		cat "$overrideEnvFile" >>"$tempEnvFile"
	fi

	# Bake the Docker Compose file
	dockerCompose "$mainComposeFile" "$overrideComposeFile" \
		--profile "$profileName" \
		--env-file "$tempEnvFile" \
		config >"$outputFile"
	returnState=$?

	rm -f "$tempEnvFile"
	return $returnState
}

###
# Define a function which identifies whether a Docker Compose file is baked.
#
# To perform this test, the given file is compared against a newly-baked file
# and the result is returned as a boolean value.
#
# @param string $1 The file to evaluate.
# @param string $2 The profile name; one of development, lab, qa, staging, or
#                  production.  Defaults to "development".
# @param string $3 The source directory to look in for the base files.
#                  Defaults to the directory of the given file.
#
# @return integer 0 if the file is baked, 1 if it is not, or 2 if there was an
#                 error evaluating the file.
##
function isBakedComposeFile() {
	local testFile profileName sourceDirectory bakedFile returnState
	testFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing test file name."}
	profileName=${2-"development"}
	sourceDirectory=${3:-"$(dirname "$testFile")"}
	bakedFile=$(mktemp)
	trap "rm -f '$bakedFile'" EXIT

	# yamlpath must be installed to perform the comparison
	if ! yaml-diff --version >/dev/null 2>&1; then
		echo "ERROR:  yamlpath is not installed or not on the PATH!" >&2
		return 2
	fi

	# Bake the Docker Compose file
	if ! dynamicBakeComposeFile "$bakedFile" "$profileName" "$sourceDirectory"
	then
		return 2
	fi

	# Compare the baked file to the test file
	yaml-diff "$testFile" "$bakedFile" >/dev/null 2>&1
	returnState=$?

	# Clean up and return the result
	rm -f "$bakedFile"
	return $returnState
}
