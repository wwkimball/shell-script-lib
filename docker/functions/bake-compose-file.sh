################################################################################
# Implement the bakeComposeFile function.
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

###
# Bake Docker Compose configuration files for a named profile.
#
# This creates a new Docker Compose file for the named profile by merging the
# base Docker Compose file with the optional override file, expanding all
# shell variables within them (from .env and any already-exported shell
# environment variables), and adding environment variables for the content of
# all env_file entries.  Remember that any .env and referenced env_file files
# must be present in or relative to the current directory.
#
# @param string $1 The output file to create with the baked configuration.
# @param string $2 The profile name; one of development, lab, qa, staging, or
#                  production.
# @param string $3 The base Docker Compose file.
# @param string $4 The optional override Docker Compose file.
#
# @return void
##
function bakeComposeFile() {
	local outputFile profileName mainComposeFile envComposeFile
	outputFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing output file name."}
	profileName=${2:?"ERROR:  ${FUNCNAME[0]}:  Missing profile name."}
	mainComposeFile=${3:?"ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file."}
	envComposeFile=$4

	dockerCompose "$mainComposeFile" "$envComposeFile" \
		--profile "$profileName" \
		config >"$outputFile"
}
