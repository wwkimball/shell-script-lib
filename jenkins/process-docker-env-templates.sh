#!/usr/bin/bash
###############################################################################
# Populate variables in Jenkins-managed Docker environment files.
#
# This engine uses template files.  The template files must be in the
# ${WORKSPACE}/docker directory and must be named to match .env*.  The
# extension of the template specifies how it is to be handled.  All
# substitutions are made from a supplied set of environment variable names.
# Processed template files are destroyed in the process.  The following
# template file extensions are recognized:
#   * A file with a ".template" extension is read, has its variables
#     substituted, and is written to a same-named file without the ".template"
#     extension.
#   * A file with a ".environment-template" extension is read, has its
#     variables substituted, and is written to a same-named file with the
#     environment name replacing the template extension.
# Any file with neither of these extensions is left alone.
#
# The environment variables to be substituted are provided as positional
# command-line arguments.  The variable names provided are evaluated to
# determine whether environment-specific variable names exist which match the
# pattern:  ${ENVIRONMENT_VARIABLE}_${ENVIRONMENT_NAME}.  When they do, the
# environment-specific variable's value is copied to the base variable as long
# as the base variable is not already set.  This allows for dynamic use of
# environment-specific values.
#
# Variable substitution permits both curly-braced (${VARIABLE}) and bare
# ($VARIABLE) variable names.  The substitution is case-sensitive.
#
# Some envrionment variables are expected to be set in the Jenkins job.  These
# include:
#   * WORKSPACE:  The Jenkins workspace directory
#   * ENVIRONMENT_NAME:  The name of the environment for which the Docker
#     environment files are being prepared.
###############################################################################
set -e
jenkinsWorkspace=${WORKSPACE:?"ERROR:  The WORKSPACE environment variable must be set!"}
dockerDir=${jenkinsWorkspace}/docker

# Create a function which accepts a base environment variable name and checks
# for the existence of the environment-specific variable.  If it exists, the
# environment-specific variable's value is copied to the base variable.
function ambiguateEnvironmentVariable() {
	local baseVarName=${1:?"ERROR:  A base environment variable name must be provided as the first positional argument to ${FUNCNAME[0]}!"}
	local envName=${2:?"ERROR:  An environment name must be provided as the second positional argument to ${FUNCNAME[0]}!"}
	local envVarName="${baseVarName}_${envName}"

	# Do nothing when the base variable already has a value
	if [ -n "${!baseVarName}" ]; then
		return
	fi

	# Because eval is used, the environment variable name must be validated
	if [[ ! "$envVarName" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
		echo "ERROR:  Invalid environment variable name:  ${envVarName}" >&2
		exit 1
	fi

	if [ -n "${!envVarName}" ]; then
		echo "Ambiguating ${envVarName} as ${baseVarName}..."
		eval "$baseVarName=\$${envVarName}"
	fi
}

# Create a function which takes a template text and performs the substitutions
function substituteTemplateVariables() {
	local templateText="$1"
	local varName braceWrappedKey bareKey substituteValue
	for varName in "${_substitutionVars[@]}"; do
		braceWrappedKey="\$\{${varName}\}"
		bareKey="\$${varName}"
		substituteValue="${!varName}"
		templateText=${templateText//${braceWrappedKey}/${substituteValue}}
		templateText=${templateText//${bareKey}/${substituteValue}}
	done
	echo "$templateText"
}

# Function to process template files
function processTemplateFiles() {
	local templateExtension=${1:?"ERROR:  A template extension must be provided as the first positional argument to ${FUNCNAME[0]}!"}
	local optionalExtension=$2
	local templateFiles=$(find "$dockerDir" -maxdepth 1 -name ".env*.${templateExtension}")
	local templateFile templateText concreteFile
	for templateFile in $templateFiles; do
		echo "Processing ${templateFile}..."
		templateText=$(cat "$templateFile")
		if [ 0 -ne $? ]; then
			echo "ERROR:  Unable to read ${templateFile}!" >&2
			exit 2
		fi

		# Write the result to the concrete file and delete the template file
		templateText=$(substituteTemplateVariables "$templateText")
		concreteFile=${templateFile%.$templateExtension}
		if [ -n "$optionalExtension" ]; then
			concreteFile="${concreteFile}.${optionalExtension}"
		fi
		echo "$templateText" >"$concreteFile"
		if [ 0 -ne $? ]; then
			echo "ERROR:  Unable to write ${concreteFile}!" >&2
			exit 3
		fi

		if ! rm -f "$templateFile"; then
			echo "WARNING:  Unable to delete ${templateFile}!"
		fi
	done
}

# Accept as command-line arguments a list of environment variable names to be
# substituted in the template files.
declare -a _substitutionVars
if [ 0 -eq $# ]; then
	echo "ERROR:  No environment variable names were supplied!" >&2
	exit 1
fi
for varName in "$@"; do
	_substitutionVars+=("$varName")
done

# Ensure that the environment name is set and convert it to lower and upper
# case for processing.
if [ -z "$ENVIRONMENT_NAME" ]; then
	echo "ERROR:  ENVIRONMENT_NAME must be set!" >&2
	exit 1
fi
lcEnvironmentName=${ENVIRONMENT_NAME,,}
ucEnvironmentName=${ENVIRONMENT_NAME^^}

# Copy environment-specific variables to the base variables provided
for varName in "${_substitutionVars[@]}"; do
	ambiguateEnvironmentVariable "$varName" "$ucEnvironmentName"
done

# Process template files
processTemplateFiles "template"
processTemplateFiles "environment-template" "$lcEnvironmentName"
