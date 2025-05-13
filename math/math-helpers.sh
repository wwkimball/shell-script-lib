###############################################################################
# Define shell helper functions for common math operations.
###############################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# This is an import helper; just import the various function definitions
# from the other files in the math directory.
_thisDir="${BASH_SOURCE[0]%/*}"
_floatsDir="${_thisDir}/floats"
source "${_floatsDir}/compare.sh"
