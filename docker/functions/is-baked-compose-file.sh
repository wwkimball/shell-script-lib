################################################################################
# Implement the isBakedComposeFile function.
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

###
# Define a function which identifies whether a Docker Compose file is baked.
#
# To perform this test, the given file is compared against a newly-baked file
# and the result is returned as a boolean value.
#
# @param string $1 The file to evaluate.
# @param string $2 The profile name; one of development, lab, qa, staging, or
#                  production.  Defaults to "development".
# @param string $3 The source directory to look in for the base files.
#                  Defaults to the directory of the given file.
#
# @return integer 0 if the file is baked, 1 if it is not, or 2 if there was an
#                 error evaluating the file.
##
function isBakedComposeFile() {
	local testFile profileName sourceDirectory bakedFile returnState
	testFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing test file name."}
	profileName=${2-"development"}
	sourceDirectory=${3:-"$(dirname "$testFile")"}
	bakedFile=$(mktemp)
	trap "rm -f '$bakedFile'" EXIT

	# yamlpath must be installed to perform the comparison
	if ! yaml-diff --version >/dev/null 2>&1; then
		echo "ERROR:  yamlpath is not installed or not on the PATH!" >&2
		return 2
	fi

	# Bake the Docker Compose file
	if ! dynamicBakeComposeFile "$bakedFile" "$profileName" "$sourceDirectory"
	then
		return 2
	fi

	# Compare the baked file to the test file
	yaml-diff "$testFile" "$bakedFile" >/dev/null 2>&1
	returnState=$?

	# Clean up and return the result
	rm -f "$bakedFile"
	return $returnState
}
