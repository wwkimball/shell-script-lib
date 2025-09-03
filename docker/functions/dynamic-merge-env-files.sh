################################################################################
# Implement the dynamicMergeEnvFiles function.
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
# Dynamically merge all relevant Docker environment variable files.
#
# All environment files in the given Docker directory will be merged which
# share the same deployment stage suffix.  Any pertinent docker-compose.*.yaml
# files will be evaluated to find all relevant service names to further inform
# the selection of environment files.  The merged content is written to the
# specified temporary file.
#
# MAINTENANCE NOTE:
# This function is deeply embedded in various scripts and other functions.  Its
# output controls key behaviors of Docker Compose and related tooling.  Any
# spurious content sent to STDOUT by this function can cause issues that are
# extremely difficult to diagnose.  As such, all non-value output MUST be sent
# to STDERR.  Only empty strings (nothing found) or actual discovered values
# should be sent to STDOUT.
#
# @param string $1 The temporary file path to write the merged environment
#                  variables to.  The caller is responsible for creating and
#                  later destroying this file.
# @param string $2 The Docker directory to inspect for environment variable
#                  files
# @param string $3 The deployment stage name, i.e.:  development, lab, qa,
#                  staging, and production.
# @param string $@ Additional, specific environment variable files to merge.
#                  When the files are already in the Docker directory, you do
#                  not need to fully-qualify these file paths.
#
# @return integer One of:
#   0 on success
#   1 when no environment files were found
#   2 when merging environment files failed
#   3 when there is an error attempting to handle the Docker Compose file(s)
#
# @example
#   tempFile=$(mktemp)
#   dynamicMergeEnvFiles "$tempFile" "/path/to/docker/files" "development" ".env.custom"
#   # Use, then destroy the merged file
#   rm -f "$tempFile"
##
function dynamicMergeEnvFiles() {
	local mergedEnvFile=${1:?"ERROR:  The merged environment file path must be provided as the first positional argument to ${FUNCNAME[0]}"}
	local dockerDir=${2:?"ERROR:  The Docker files directory must be provided as the second positional argument to ${FUNCNAME[0]}"}
	local deploymentStage=${3:?"ERROR:  The deployment stage must be provided as the third positional argument to ${FUNCNAME[0]}"}
	local envFile returnCode tempMergeFile varName tempFile2
	declare -a envFiles
	shift 3

	# Discover all relevant environment files
	if ! discoverEnvFiles envFiles "$dockerDir" "$deploymentStage" "$@"; then
		returnCode=$?
		if [ "$returnCode" -eq 1 ]; then
			logWarningToError "No environment files found to merge."
		fi
		return $returnCode
	fi

	# Initialize the merged file (truncate if it exists)
	if ! >"$mergedEnvFile"; then
		logError "Failed to initialize merged environment file:  $mergedEnvFile"
		return 2
	fi

	# Merge all discovered environment variable files
	returnCode=1
	tempMergeFile=$(mktemp)

	for envFile in "${envFiles[@]}"; do
		if [ -f "$envFile" ]; then
			# Indicate that at least one file has been found when, so far, none
			# have.
			if [ "$returnCode" -eq 1 ]; then
				returnCode=0
			fi

			logDebugToError "Merging environment variables from:  $envFile"

			# DEBUG:  Add a header comment to identify the source file
			cat >>"$tempMergeFile" <<EOF
# Environment variables from:  $envFile
EOF

			# Process each line from the environment file
			while IFS= read -r line || [ -n "$line" ]; do
				# Skip empty lines and comments
				if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
					echo "$line" >>"$tempMergeFile"
					continue
				fi

				# Extract variable name from assignments
				if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)= ]]; then
					varName="${BASH_REMATCH[1]}"

					# Remove any previous occurrences of this variable from the
					# temp file.
					if [ -s "$tempMergeFile" ]; then
						tempFile2=$(mktemp)

						# Use grep to exclude lines that set this variable
						grep -v "^[[:space:]]*${varName}=" "$tempMergeFile" >"$tempFile2" || true
						mv "$tempFile2" "$tempMergeFile"
					fi
				fi

				# Append the current line
				echo "$line" >>"$tempMergeFile"
			done <"$envFile"
		else
			logWarningToError "Environment variable file not found:  $envFile"
		fi
	done

	# Move the processed content to the final merged file
	if [ "$returnCode" -eq 0 ]; then
		if ! mv "$tempMergeFile" "$mergedEnvFile"; then
			logError "Failed to finalize merged environment file:  $mergedEnvFile"
			returnCode=2
		fi
	fi
	rm -f "$tempMergeFile"

	# DEBUG
	if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
		logDebugToError "Merged environment file created successfully with content:"
		cat "$mergedEnvFile" | while read -r line; do
			logDebugToError "  $line"
		done
	fi

	return $returnCode
}
