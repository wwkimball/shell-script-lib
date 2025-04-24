#!/usr/bin/bash
###############################################################################
# Populate variables in template files.
#
# This engine uses template files.  These will be identified by the presence of
# the string, ".template", anywhere in the file name.  This string will be
# removed from the file name when the template is processed.  For example:
#   * foo.template -> foo
#   * foo.template.txt -> foo.txt
#   * .env.template -> .env
#   * .env.template.production -> .env.production
#   * .template.env -> .env
#
# The environment variables to be substituted are provided as positional
# command-line arguments.  The variable names provided are evaluated to
# determine whether deployment stage-specific variable names exist which match
# the pattern:  ${ENVIRONMENT_VARIABLE}_${DEPLOYMENT_STAGE}.  When they do, the
# deployment stage-specific variable's value is copied to the base variable as
# long as the base variable is not already set.  This allows for dynamic use of
# deployment stage-specific values.
#
# Variable substitution permits both curly-braced, ${ENVIRONMENT_VARIABLE}, and
# bare, $ENVIRONMENT_VARIABLE, variable names.  The substitution is
# case-sensitive.
#
# The following environment variables MUST be set to control the behavior of
# this script:
#   * TEMPLATE_DIRECTORY:  The directory in which the template files are found.
#
# The following environment variables MAY be set to control the behavior of
# this script:
#   - LIB_DIRECTORY:  The base directory of the library in which this script
#     resides.
#   - TEMPLATE_EXTENSION:  The file extension of the template files.  The
#     default value is ".template".
#   - DEPLOYMENT_STAGE:  The name of the deployment stage for which the files
#     are being prepared.
#   - LOG_LEVEL:  Normal, warning, and error messages are always output.  The
#     following logging levels are supported to increase verbosity:
#     - VERBOSE:  Verbose messages.
#     - DEBUG:  Debugging information.
###############################################################################
set -e
templateDirectory=${TEMPLATE_DIRECTORY:?"ERROR:  The TEMPLATE_DIRECTORY environment variable must be set!"}

# Import the logging facility
if [ -z "$LIB_DIRECTORY" ]; then
	MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	LIB_DIRECTORY="${MY_DIRECTORY}/../../"
	readonly MY_DIRECTORY LIB_DIRECTORY
fi
loggingLib="${LIB_DIRECTORY}/logging/set-logger.sh"
if ! source "$loggingLib"; then
	echo "ERROR:  Unable to source ${loggingLib}!" >&2
	exit 2
fi
unset loggingLib

# Check whether the deployment stage is set and convert it to lower and upper
# case for processing when it is.
ambiguateEnvironmentVariables=false
ucEnvironmentName=''
if [ -n "$DEPLOYMENT_STAGE" ]; then
	ambiguateEnvironmentVariables=true
	ucEnvironmentName=${DEPLOYMENT_STAGE^^}
fi

# Check whether the template extension is set and convert it to lower case for
# processing when it is.
templateExtension=${TEMPLATE_EXTENSION:-".template"}
templateExtension=${templateExtension,,}
if [[ ! "$templateExtension" =~ ^\.[a-zA-Z0-9_]+$ ]]; then
	errorOut 1 "Invalid template extension:  ${templateExtension}"
fi

# Check whether the template directory exists, is a directory, and is readable
if [ ! -d "$templateDirectory" ] || [ ! -r "$templateDirectory" ]; then
	errorOut 1 "The template directory, ${templateDirectory}, does not exist, is not a directory, or cannot be read by this process!"
fi

# Check whether the template directory is writable
if [ ! -w "$templateDirectory" ]; then
	errorOut 1 "Files in template directory, ${templateDirectory}, cannot be written by this process!"
fi

# Create a function which accepts a base environment variable name and checks
# for the existence of the environment-specific variable.  If it exists, the
# environment-specific variable's value is copied to the base variable.
function ambiguateEnvironmentVariable() {
	local baseVarName=${1:?"ERROR:  A base environment variable name must be provided as the first positional argument to ${FUNCNAME[0]}!"}
	local deploymentStage=${2:?"ERROR:  An environment name must be provided as the second positional argument to ${FUNCNAME[0]}!"}
	local envVarName="${baseVarName}_${deploymentStage}"

	# Do nothing when the base variable already has a value
	if [ -n "${!baseVarName}" ]; then
		return
	fi

	# Because eval is used, the environment variable name must be validated
	if [[ ! "$envVarName" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
		errorOut 1 "Invalid environment variable name:  ${envVarName}"
	fi

	if [ -n "${!envVarName}" ]; then
		logVerbose "Ambiguating ${envVarName} as ${baseVarName}..."
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
	local templateFiles=$(find "$templateDirectory" -maxdepth 1 -iname "*.${templateExtension}")
	local templateFile templateText concreteFile
	for templateFile in $templateFiles; do
		logInfo "Processing ${templateFile}..."
		templateText=$(cat "$templateFile")
		if [ 0 -ne $? ]; then
			errorOut 2 "Unable to read ${templateFile}!"
		fi

		# Perform variable substitution
		templateText=$(substituteTemplateVariables "$templateText")

		# Identify the concrete filename by removing the template string
		concreteFile=${templateFile%${templateExtension}*}
		concreteFile=${concreteFile##*/}
		concreteFile="${templateDirectory}/${concreteFile}"

		# Write the result to the concrete file and delete the template file
		echo "$templateText" >"$concreteFile"
		if [ 0 -ne $? ]; then
			errorOut 3 "Unable to write ${concreteFile}!"
		fi

		if ! rm -f "$templateFile"; then
			logWarning "Unable to delete ${templateFile}!"
		fi
	done
}

# Accept as command-line arguments a list of environment variable names to be
# substituted in the template files.
declare -a _substitutionVars
if [ 0 -eq $# ]; then
	errorOut 1 "No environment variable names were supplied!"
fi
for varName in "$@"; do
	_substitutionVars+=("$varName")
done

# Copy environment-specific variables to the base variables provided
if $ambiguateEnvironmentVariables; then
	for varName in "${_substitutionVars[@]}"; do
		ambiguateEnvironmentVariable "$varName" "$ucEnvironmentName"
	done
fi

# Process template files
processTemplateFiles "$templateExtension"
