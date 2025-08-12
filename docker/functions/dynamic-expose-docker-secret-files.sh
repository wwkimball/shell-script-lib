################################################################################
# Implement the dynamicExposeDockerSecretFiles function.
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
# Discover and expose (export) all Docker Secret files.
#
# Only files with a .txt extension are exposed.  The name of the file sets the
# exposed environment variable name (in all upper-case).
#
# @param string $1 The directory to search for Docker Secret files.
#
# @returns integer 0 on success; 1 on failure
##
function dynamicExposeDockerSecretFiles {
	local searchDir=${1:?"ERROR:  The directory to search for Docker Secret files must be provided as the first positional argument to ${FUNCNAME[0]}"}
	local secretFile baseName envVarName

	# Validate that the directory exists
	if [ ! -d "$searchDir" ]; then
		logError "Directory not found:  $searchDir"
		return 1
	fi

	# Loop through all of the *.txt files in the specified directory
	for secretFile in "$searchDir"/*.txt; do
		# Extract the base name of the file (without the directory path)
		baseName=$(basename "$secretFile")

		# Convert the base name to upper case to create the environment variable name
		envVarName=$(echo "$baseName" | tr '[:lower:]' '[:upper:]')

		# Expose the Docker Secret file as an environment variable
		export "$envVarName"="$(<"$secretFile")"
		logInfo "Exposed Docker Secret file:  $secretFile as $envVarName"
	done

	return 0
}
