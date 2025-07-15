################################################################################
# Define shell helper functions for common git operations.
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# This is an import helper; just import the various function definitions
# from the other files in the git directory.
_thisDir="${BASH_SOURCE[0]%/*}"
_functionsDir="${_thisDir}/functions"
for _funcFile in "${_functionsDir}"/*.sh; do
	source "$_funcFile"
done
unset _thisDir _functionsDir _funcFile
