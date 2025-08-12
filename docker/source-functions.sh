###############################################################################
# Source all helper functions in this sub-library.
###############################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# This is an import helper; just import the various function definitions
# from the other files in the functions directory.
_thisDir="${BASH_SOURCE[0]%/*}"
_funcsDir="${_thisDir}/functions"
for _funcFile in "${_funcsDir}"/*.sh; do
	if [ -f "$_funcFile" ]; then
		if ! source "$_funcFile"; then
			echo "ERROR:  Unable to source ${_funcFile}!" >&2
			exit 2
		fi
	fi
done
unset _thisDir _funcsDir _funcFile
