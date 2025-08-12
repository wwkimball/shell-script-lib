################################################################################
# Implement the dockerCompose function.
################################################################################
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
	local mainComposeFile envComposeFile exitCode
	mainComposeFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file."}
	envComposeFile=$2
	shift 2
	exitCode=0

	if [ ! -z "$envComposeFile" -a -f "$envComposeFile" ]; then
		docker compose -f "$mainComposeFile" -f "$envComposeFile" "$@"
		exitCode=$?
	else
		docker compose -f "$mainComposeFile" "$@"
		exitCode=$?
	fi

	return $exitCode
}
