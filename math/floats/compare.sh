################################################################################
# Defines a function, compareFloats, which compares two floating point numbers.
#
# Copyright 2001, 2018, 2025 William W. Kimball, Jr. MBA MSIS
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
# Compare two floating-point numbers.
#
# @param <string> $1 The left hand side (LHS) number to compare.
# @param <string> $2 The right hand side (RHS) number to compare.
#
# @return <integer> One of:
#   * 0 An error occurred while comparing the numbers; the error message is
#     printed to STDERR.
#   * 1 The LHS number is less than the RHS number.
#   * 2 The LHS number is equal to the RHS number.
#   * 3 The LHS number is greater than the RHS number.
#
# @example
#   # Compare two floating-point numbers
#   lhs=1.2
#   rhs=2.1
#   compareFloats $lhs $rhs
#   result=$?
#   case $result in
#       1) echo "${lhs} is less than ${rhs}" ;;
#       2) echo "${lhs} is equal to ${rhs}" ;;
#       3) echo "${lhs} is greater than ${rhs}" ;;
#       *) echo "An error occurred while comparing the numbers" ;;
#   esac
##
function compareFloats {
	# Get the two numbers to compare
	local lhs_in=$1
	local rhs_in=$2

	# Check that the two values are not empty
	if [ -z "$lhs_in" ]; then
		logError "${FUNCNAME[0]} received an empty LHS value."
		return 0
	fi
	if [ -z "$rhs_in" ]; then
		logError "${FUNCNAME[0]} received an empty RHS value."
		return 0
	fi

	# Short-circuit when the two values are identical
	if [ "$lhs_in" == "$rhs_in" ]; then
		return 2
	fi

	# This function does not comprehensively compare version numbers!  However,
	# it can be abused to compare floating-point numbers that come from
	# otherwise SemVer-compatible values.  As such, read the inputs as if they
	# were valid floating-point numbers ALLOWING FOR ONLY ONE PERIOD, but only
	# up to the first non-numeric character.
	lhs=$(echo "$lhs_in" | sed -E 's/^([[:digit:]]+(\.[[:digit:]]+)?).*/\1/')
	rhs=$(echo "$rhs_in" | sed -E 's/^([[:digit:]]+(\.[[:digit:]]+)?).*/\1/')

	# If either remaining input number is still not a valid floating-point
	# number, then print an error message and bail out.
	if [[ ! "$lhs" =~ ^[[:digit:]]+(\.[[:digit:]]+)?$ ]]; then
		logError "Invalid first number, ${lhs}."
		return 0
	fi
	if [[ ! "$rhs" =~ ^[[:digit:]]+(\.[[:digit:]]+)?$ ]]; then
		logError "Invalid second number, ${rhs}."
		return 0
	fi

	# Short-circuit when the two remaining values are identical
	if [ "$lhs" == "$rhs" ]; then
		return 2
	fi

	# If the bc command is available, then use it to compare the numbers
	if [ ! -z "$(which bc 2>/dev/null)" ]; then
		local result=$(echo "$lhs < $rhs" | bc)
		if [ "$result" -eq 1 ]; then
			return 1
		fi
		result=$(echo "$lhs > $rhs" | bc)
		if [ "$result" -eq 1 ]; then
			return 3
		fi
		return 2
	fi

	# If awk is available, then use it to compare the numbers
	if [ ! -z "$(which awk 2>/dev/null)" ]; then
		local result
		local os_type=$(uname -s)
		local os_release=""

		# Detect the operating system
		case "$os_type" in
			"Linux")
				if [ -f /etc/rocky-release ]; then
					os_release="rocky"
				elif [ -f /etc/redhat-release ] && grep -q "Rocky Linux" /etc/redhat-release 2>/dev/null; then
					os_release="rocky"
				elif [ -f /etc/lsb-release ] && grep -q "Ubuntu" /etc/lsb-release 2>/dev/null; then
					os_release="ubuntu"
				elif [ -f /etc/os-release ]; then
					if grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
						os_release="ubuntu"
					elif grep -q "Rocky Linux" /etc/os-release 2>/dev/null; then
						os_release="rocky"
					fi
				fi
				;;
			"Darwin")
				os_release="macos"
				;;
		esac

		# Use OS-specific awk syntax
		case "$os_release" in
			"rocky")
				# Rocky Linux 8+ requires explicit string concatenation and different quoting
				result=$(awk -v n1="$lhs" -v n2="$rhs" 'BEGIN {
					if (n1 + 0 < n2 + 0) { print "1" }
					else if (n1 + 0 > n2 + 0) { print "3" }
					else { print "2" }
				}')
				;;
			"ubuntu"|"macos"|*)
				# Standard awk syntax for Ubuntu, macOS, and other systems
				result=$(awk -v n1="$lhs" -v n2="$rhs" 'BEGIN {
					if (n1 < n2) { print 1 }
					else if (n1 > n2) { print 3 }
					else { print 2 }
				}')
				;;
		esac

		return $result
	fi

	# If neither bc nor awk are available, then break the numbers apart into
	# arrays and compare each array element
	local partIndex
	local -a lhsParts rhsParts
	IFS=. read -ra lhsParts <<< "$lhs"
	IFS=. read -ra rhsParts <<< "$rhs"
	for ((partIndex=0; partIndex<${#lhsParts[@]}; partIndex++)); do
		if [ ${lhsParts[$partIndex]} -lt ${rhsParts[$partIndex]} ]; then
			return 1
		fi
		if [ ${lhsParts[$partIndex]} -gt ${rhsParts[$partIndex]} ]; then
			return 3
		fi
	done
	return 2
}
