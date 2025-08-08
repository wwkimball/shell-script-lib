################################################################################
# Implement the dynamicBakeComposeFile function.
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

###
# Bake Docker Compose configuration files for a named profile, dynamically.
#
# This function dynamically identifies the base and override files based on a
# given source directory to look in along with an identifier to seek as part
# of the filenames.  This is useful for baking configuration files for a
# specific environment, such as "development", "production", and so on but
# without having to hard-code the filenames and independently identify
# whether any/all of the files exist.
#
# The identifier will be sought by injecting it before the .yaml extension of
# the compose file, but after ".env" for the environment file.  The base
# compose file is always "docker-compose.yaml" and the base environment file is
# always ".env".  So, when the identifier is "development", the override
# compose file would be "docker-compose.development.yaml" and the override
# environment file would be ".env.development".
#
# @param string $1 The output file to create with the baked configuration.
# @param string $2 The profile name; one of development, lab, qa, staging,
#                  production, and so on.  This is also the identifier to seek
#				   in the filenames.  Defaults to "development".
# @param string $3 The source directory to look in for the base files.
#                  Defaults to "docker".
#
# @return integer 0 if the files were baked successfully, non-zero otherwise.
#
# @example
#   dynamicBakeComposeFile "my-baked-config.yaml"
#   dynamicBakeComposeFile "my-baked-config.yaml" "production"
#   dynamicBakeComposeFile "my-baked-config.yaml" "staging" "$(pwd)"
##
function dynamicBakeComposeFile() {
	local outputFile profileName sourceDirectory mainComposeFile \
		overrideComposeFile tempEnvFile altMainComposeFile \
		altOverrideComposeFile returnState
	outputFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing output file name."}
	profileName=${2:-"development"}
	sourceDirectory=${3:-"docker"}
	mainComposeFile="${sourceDirectory}/docker-compose.yaml"
	overrideComposeFile="${sourceDirectory}/docker-compose.${profileName}.yaml"
	returnState=0

	if [ ! -f "$mainComposeFile" ]; then
		# Allow for the incorrect ".yml" extension
		altMainComposeFile="${sourceDirectory}/docker-compose.yml"
		if [ -f "$altMainComposeFile" ]; then
			mainComposeFile="$altMainComposeFile"
		else
			echo "ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file:  ${mainComposeFile}" >&2
			return 2
		fi
	fi

	if [ ! -f "$overrideComposeFile" ]; then
		# Allow for the incorrect ".yml" extension
		altOverrideComposeFile="${sourceDirectory}/docker-compose.${profileName}.yml"
		if [ -f "$altOverrideComposeFile" ]; then
			overrideComposeFile="$altOverrideComposeFile"
		else
			overrideComposeFile=''
		fi
	fi

	# Either, neither, or both of the environment variable files may be
	# present.  Further, there may be any number of additional service-specific
	# environment variable files to consider.  Simplify the logic by creating a
	# temporary file to hold the environment variables to be used.
	tempEnvFile=$(mktemp)
	dynamicMergeEnvFiles "$tempEnvFile" "$sourceDirectory" "$profileName"

	# Bake the Docker Compose file
	dockerCompose "$mainComposeFile" "$overrideComposeFile" \
		--profile "$profileName" \
		--env-file "$tempEnvFile" \
		config >"$outputFile"
	returnState=$?

	rm -f "$tempEnvFile"
	return $returnState
}
