################################################################################
# Implement the startAndAwaitService function.
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

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
