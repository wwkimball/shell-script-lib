###############################################################################
# Define a function to decrement a version number in the format X.Y[.Z][...].
###############################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# Dynamically load the common logging functions
if [ -z "$LIB_DIRECTORY" ]; then
	# The common library directory is not set, so set it to the default value
	MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	PROJECT_DIRECTORY="$(cd "${MY_DIRECTORY}/../../" && pwd)"
	LIB_DIRECTORY="${STD_SHELL_LIB:-"${PROJECT_DIRECTORY}/lib"}"
	readonly MY_DIRECTORY PROJECT_DIRECTORY LIB_DIRECTORY
fi
setLoggerSource="${LIB_DIRECTORY}/logging/set-logger.sh"
if ! source "$setLoggerSource"; then
	echo "ERROR:  Unable to source ${setLoggerSource}!" >&2
	exit 2
fi
unset setLoggerSource

###
# Decrement a version number in the format X.Y[.Z][...].
#
# This function works only against version numbers composed entirely of digits
# that are separated by dots.  THIS IS NOT SEMVER COMPLIANT!  The presence of
# any non-digit characters in the version number will cause the function to
# fail.  There must be at least one segment in the version number.
#
# Note that leading zeros are ignored.  For example, the version number
# "01.02.03" is treated as "1.2.3" for the purpose of decrementing the first
# qualifying (non-zero) segment.  As such, an input of "01.02" will result in
# "01.1".
#
# Only the last segment of the version number is decremented.  When the last
# segment is 0, it is decremented to 9 and the second segment is decremented,
# and so on.  If the version number is already at 0, it is returned as-is.
#
# @param <string> $1 The version number to decrement.
#
# @return <integer> 0 on success; non-zero on failure:
#   * 1:  The version number is empty.
#   * 2:  The version number is not in the correct format.
#   * 3:  An error occurred while decrementing the version number; the error
#         message is printed to STDERR.
#   * 4:  The version number is already at 0 or otherwise could not be
#         decremented.
# @return STDOUT <string> The decremented version number.
# @return STDERR <string> An error message if an error occurred.
#
# @example
#   # Decrement a version number
#   version="1.2.3"
#   priorVersion=$(decrementDottedVersion "$version")
#   echo "Decremented version: $priorVersion"  # Returns "1.2.2"
#
# @example
#   # Decrement a version number with a zero segment
#   version="1.2.0"
#   priorVersion=$(decrementDottedVersion "$version")
#   echo "Decremented version: $priorVersion"  # Returns "1.1.9"
#
# @example
#   # Decrement a version number with all segments at zero
#   version="0.0.0"
#   priorVersion=$(decrementDottedVersion "$version")
#   echo "Decremented version: $priorVersion"  # Returns "0.0.0"
##
function decrementDottedVersion {
	# Get the version number to decrement
	local dottedVersion=${1:?"${FUNCNAME[0]} received an empty version number."}

	# Split the version number into its components
	local IFS='.'
	read -ra versionComponents <<< "$dottedVersion"
	local componentCount=${#versionComponents[@]}
	if [ $componentCount -eq 0 ]; then
		logError "${FUNCNAME[0]} could not parse the version number:  $dottedVersion"
		return 2
	fi

	# Process the components from right to left
	local priorVersion=""
	local wasDecremented=false
	local lastIndex=$((componentCount - 1))
	local i
	for (( i=componentCount-1; i>=0; i-- )); do
		local versionComponent="${versionComponents[i]}"
		if [[ ! "$versionComponent" =~ ^[0-9]+$ ]]; then
			logError "${FUNCNAME[0]} received a non-digit component, ${versionComponent}, in version number:  $dottedVersion"
			return 3
		fi

		# Once a component has been decremented, all subsequent components are
		# just prepended to the result.
		if $wasDecremented; then
			# Just prepend the present component to the result
			priorVersion="${versionComponent}.${priorVersion}"
			continue
		fi

		# Decrement the present component of the version number
		if [ "$versionComponent" -gt 0 ]; then
			versionComponent=$((versionComponent - 1))
			wasDecremented=true
		else
			versionComponent=9
		fi

		# Prepend the present component to the result
		if [ $i -eq $lastIndex ]; then
			priorVersion="$versionComponent"
		else
			priorVersion="${versionComponent}.${priorVersion}"
		fi
	done

	# When no component could be decremented, return the original version
	# number.  It is up to the caller to determine whether this is an error.  It
	# will occur when the version number is 0 or all components are at 0.
	if ! $wasDecremented; then
		echo "$dottedVersion"
		return 4
	fi

	# Return the decremented version number
	echo "$priorVersion"
}
