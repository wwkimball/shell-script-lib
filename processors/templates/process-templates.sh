#!/bin/bash
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
# The following environment variables MAY be set to specify the default values
# for certain command-line arguments:
#   - TEMPLATE_DIRECTORY:  The directory in which the template files are found.
#   - TEMPLATE_EXTENSION:  The file extension of the template files.  The
#     default value is ".template".
#   - DEPLOYMENT_STAGE:  The name of the deployment stage for which the files
#     are being prepared.
#   - LOG_LEVEL:  Normal, warning, and error messages are always output.  The
#     following logging levels are supported to increase verbosity:
#     - VERBOSE:  Verbose messages.
#     - DEBUG:  Debugging information.
#
# Copyright 2025 William W. Kimball, Jr. MBA MSIS
# All rights reserved.
###############################################################################
# Due to the destructive nature of this script, it shall bail out on any error
# condition.  This includes any command which returns a non-zero exit status
# that is not explicitly handled within this script.
set -e

# Constants
MY_VERSION='2025.04.24-1'
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIRECTORY="${MY_DIRECTORY}/../../"
readonly MY_VERSION MY_DIRECTORY LIB_DIRECTORY

# Import the logging facility
loggingLib="${LIB_DIRECTORY}/logging/set-logger.sh"
if ! source "$loggingLib"; then
	echo "ERROR:  Unable to source ${loggingLib}!" >&2
	exit 2
fi
unset loggingLib

# Process command-line arguments, if there are any; some accept environment
# variables as their default values.
_ambiguateEnvironmentVariables=false
_deploymentStage=${DEPLOYMENT_STAGE:-""}
_hasErrors=false
_logLevel=${LOG_LEVEL:-"NORMAL"}
_templateDirectory=${TEMPLATE_DIRECTORY:-$(pwd)}
_templateExtension=${TEMPLATE_EXTENSION:-".template"}
_ucDeploymentStage=''
declare -a _substitutionVars
while [ $# -gt 0 ]; do
	case $1 in
		-d|--directory)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_templateDirectory="$2"
				shift
			fi
			;;

		-e|--extension)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_templateExtension="$2"
				shift
			fi
			;;

		-h|--help)
			cat <<EOHELP
$0 [OPTIONS] [--] [VARIABLE_NAME ...]

This script processes template files in a specified directory, interpolating
environment variables into the template files.  In order to facilitate and
control the substitutions, this script accepts a list of environment variable
names to be used as positional arguments.  The template files are identified
by the presence of a special extension within their file name, which is
".template", by default (and can be changed by setting -e|--extension).  This
extension is removed from the file name when the template is processed.  See
other options for more information and additional control mechanisms.

OPTIONS include:
  -d DIRECTORY, --directory DIRECTORY
       The directory in which the template files are found.  The default value
       is the current working directory.
  -e EXTENSION, --extension EXTENSION
       The removable extension of the target template files.  A dot (.) must be
       the first character of the EXTENSION.  The default value is ".template".
  -h, --help
       Display this help message and exit.
  -s STAGE, --stage STAGE
       The optional name of the deployment stage for which the files are being
       prepared.  When set, each VARIABLE_NAME will be checked for the existence
       of a deployment stage-specific variable name matching the pattern:
       \${VARIABLE_NAME}_\${DEPLOYMENT_STAGE}.  If it exists, the value of the
       deployment stage-specific variable will be copied to the base variable
       name AS LONG AS the base variable is unset at the time of evaluation.
       This allows for the dynamic use of deployment stage-specific values.
       Note that any value supplied will be cast to upper-case for evaulation.
       The default value is empty.
  -v, --verbose
       Enable verbose logging.  This option may be specified up to twice to
	   increase verbosity from verbose to debug.
  --version
       Display the version of this script and exit.

EOHELP
			exit 0
			;;

		-s|--stage)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_deploymentStage="$2"
				shift
			fi
			;;

		-v|--verbose)
			# Increase the verbosity of output logging
			case $_logLevel in
				# NORMAL->VERBOSE
				NORMAL)
					_logLevel="VERBOSE"
					;;
				# VERBOSE->DEBUG; ignore anything else
				*)
					_logLevel="DEBUG"
					;;
			esac
			;;

		-v|--version)
			echo "$0 ${MY_VERSION}"
			exit 0
			;;

		--)	# Explicit end of options
			shift
			break
			;;

		-*)
			logError "Unknown option:  $1"
			_hasErrors=true
			;;

		*)	# Implicit end of options
			break
			;;
	esac

	shift
done

# Check whether the template directory exists, is a directory, and is readable
if [ ! -d "$_templateDirectory" ] || [ ! -r "$_templateDirectory" ]; then
	logError "The template directory, ${_templateDirectory}, does not exist, is not a directory, or cannot be read by this process!"
	_hasErrors=true
fi

# Check whether the template directory is writable
if [ ! -w "$_templateDirectory" ]; then
	logError "Files in template directory, ${_templateDirectory}, cannot be written by this process!"
	_hasErrors=true
fi

# Check whether the template extension is set and is valid
if [[ ! "$_templateExtension" =~ ^\.[a-zA-Z0-9_]+$ ]]; then
	logError "Invalid template extension:  ${_templateExtension}"
	_hasErrors=true
fi

# There must be at least one environment variable name provided
if [ 0 -eq $# ]; then
	logError "No environment variable names were supplied for template interpolation!"
	_hasErrors=true
fi

# Bail when there are any errors
if $_hasErrors; then
	exit 1
fi

# Accept the remaining arguments as environment variable names to be
# interpolated into the template files.  The variable names are stored in an
# array for later processing.
for _substitutionVar in "$@"; do
	_substitutionVars+=("$_substitutionVar")
done

# Check whether the deployment stage is set and convert it to upper-case for
# processing when it is.
if [ -n "$_deploymentStage" ]; then
	_ambiguateEnvironmentVariables=true
	_ucDeploymentStage=${_deploymentStage^^}
fi

# Create a function which accepts a base environment variable name and checks
# for the existence of the deployment stage-specific variable.  If it exists,
# the deployment stage-specific variable's value is copied to the base variable.
function ambiguateEnvironmentVariable() {
	local baseVarName=${1:?"ERROR:  A base environment variable name must be provided as the first positional argument to ${FUNCNAME[0]}!"}
	local deploymentStage=${2:?"ERROR:  A deployment stage name must be provided as the second positional argument to ${FUNCNAME[0]}!"}
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
	local templateDirectory=${1:?"ERROR:  A template directory must be provided as the first positional argument to ${FUNCNAME[0]}!"}
	local templateExtension=${2:?"ERROR:  A template extension must be provided as the second positional argument to ${FUNCNAME[0]}!"}
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

# Copy deployment stage-specific variables to the base variables provided
if $_ambiguateEnvironmentVariables; then
	for varName in "${_substitutionVars[@]}"; do
		ambiguateEnvironmentVariable "$varName" "$_ucDeploymentStage"
	done
fi

# Process template files
processTemplateFiles "$_templateDirectory" "$_templateExtension"
