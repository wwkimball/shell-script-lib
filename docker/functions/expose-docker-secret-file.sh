################################################################################
# Defines a function which exposes a secret file as an environment variable.
#
# Copyright 2025 William W. Kimball, Jr. MBA MSIS
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
# Expose a secret file's content as an environment variable.
#
# Only the first line of the secret file is read and set as the value of the
# specified environment variable.
#
# @param <string> $1 The name of the environment variable to set.
# @param <string> $2 (OPTIONAL) The name of the Docker secret to expose; the
#   default is the lower-case version of $1.  It is useful to set this whenever
#   you need to use a different name for the secret file than the environment
#   variable name.  You can also set this whenever the secret filename is case-
#   sensitive and is not a lower-case version of the environment variable name.
#
# @return <integer> One of:
#   * 0 The environment variable was set successfully.
#   * 1 At least one mandatory argument was not provided.
#   * 2 The secret file does not exist.
#   * 3 An error occurred while reading the secret file; the error message is
#     printed to STDERR.
#
# @example
#   # Expose a secret file as an environment variable
#   exposeSecretFile "MY_SECRET" "/run/secrets/my_secret"
##
function exposeDockerSecretFile {
	# Get the name of the environment variable to set
	local envVarName=${1:?"ERROR:  An environment variable name must be provided as the first positional argument to ${FUNCNAME[0]}."}
	local secretName=${2:-${envVarName,,}}
	local secretFilePath="/run/secrets/${secretName}"
	local secretValue=""

	# Check that the secret file exists
	if [ ! -f "$secretFilePath" ]; then
		logError "${FUNCNAME[0]}:  File not found:  '${secretFilePath}'."
		return 2
	fi

	# Read the secret file and set the environment variable
	if ! secretValue=$(head -1 "$secretFilePath"); then
		logError "${FUNCNAME[0]}:  Failed to read secret file:  '${secretFilePath}'."
		return 3
	fi

	# Export the environment variable
	export "${envVarName}=${secretValue}"
}
