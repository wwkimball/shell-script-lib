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
_forceOverwrite=false
_hasErrors=false
_logLevel=${LOG_LEVEL:-"NORMAL"}
_preserveTemplateFiles=false
_templateDirectory=${TEMPLATE_DIRECTORY:-$(pwd)}
_templateDirectoriesSet=false
_templateExtension=${TEMPLATE_EXTENSION:-".template"}
_ucDeploymentStage=''
declare -a _substitutionVars
declare -a _templateDirectories
while [ $# -gt 0 ]; do
	case $1 in
		-d|--directory)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_templateDirectoriesSet=true
				_templateDirectories+=("$2")
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

		-f|--force)
			# Force overwriting existing concrete files
			_forceOverwrite=true
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
       A directory in which the template files are found.  The default value
       can be set via the TEMPLATE_DIRECTORY environment variable.  This option
       may be specified multiple times to process multiple directories.  Present
       default:
       ${_templateDirectory}
  -e EXTENSION, --extension EXTENSION
       The removable extension of the target template files.  A dot (.) must be
       the first character of the EXTENSION.  The default value can be set via
       the TEMPLATE_EXTENSION environment variable.  Present default:
       ${_templateExtension}
  -f, --force
       Force overwriting existing concrete files.  By default, this script will
       not overwrite existing files.
  -h, --help
       Display this help message and exit.
  -p, --preserve
       Preserve the template files after processing.  By default, this script
       will delete the template files after processing.
  -s STAGE, --stage STAGE
       The optional name of the deployment stage for which the files are being
       prepared.  When set, each VARIABLE_NAME will be checked for the existence
       of a deployment stage-specific variable name matching the pattern:
       \${VARIABLE_NAME}_\${DEPLOYMENT_STAGE}.  If it exists, the value of the
       deployment stage-specific variable will be copied to the base variable
       name AS LONG AS the base variable is unset at the time of evaluation.
       This allows for the dynamic use of deployment stage-specific values.
       Note that any value supplied will be cast to upper-case for evaulation.
       The default value is empty.  The default value can be set via the
       DEPLOYMENT_STAGE environment variable.  Present default:
       ${_deploymentStage}
  -v, --verbose
       Enable verbose logging.  This option may be specified up to twice to
       increase verbosity from verbose to debug.
  --version
       Display the version of this script and exit.

EOHELP
			exit 0
			;;

		-p|--preserve)
			# Preserve the template files after processing
			_preserveTemplateFiles=true
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

		--version)
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

# Promote the assigned log level
export LOG_LEVEL=$_logLevel

# Ensure there is at least one template directory
if ! $_templateDirectoriesSet; then
	_templateDirectories+=("$_templateDirectory")
fi

# Check whether the template directory exists and is a directory
if [ ! -d "$_templateDirectory" ]; then
	logError "The template directory, ${_templateDirectory}, does not exist, is not a directory, or cannot be read by this process!"
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
	logDebug "Exiting with errors..."
	exit 1
fi

# Edge Case:  BASH version 5.0 introduced a change in the way that substitutions
# are performed during variable expansion.  This change causes substitution
# values containing an & character to be replaced with the matched variable
# name at the &.  This looks like:
#  * Template:  "${MY_VARIABLE}"
#  * Value:  "Hello & World"
#  * Result:  "Hello ${MY_VARIABLE} World" (not recursively expanded)
# This is a serious problem because it corrupts the substitution process.  The
# solution is to detect BASH versions >= 5.0 and to replace the & character with
# its escaped version, \&.  Because subsitution occurs in a loop, determination
# of the extra escape is performed, here.  To be safe, we will also escape all
# other special characters in the substitution value.  This is done by using the
# printf command with the %q format specifier.
_escapeSpecialCharacters=false
if [[ $BASH_VERSION =~ ^([0-9]+\.[0-9]+).+$ ]]; then
	bashMajMin=${BASH_REMATCH[1]}
	if [ 0 -ne $(bc <<< "${bashMajMin} >= 5.0") ]; then
		# BASH version >= 5.0
		_escapeSpecialCharacters=true
		logDebug "BASH version ${BASH_VERSION} detected; escaping special characters in substitution values..."
	else
		# BASH version < 5.0
		logDebug "BASH version ${BASH_VERSION} detected; not escaping special characters in substitution values..."
	fi
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

		if $_escapeSpecialCharacters; then
			substituteValue=$(printf "%q" "$substituteValue")
		fi

		templateText=${templateText//${braceWrappedKey}/${substituteValue}}
		templateText=${templateText//${bareKey}/${substituteValue}}
	done
	echo "$templateText"
}

# Function to process template files
function processTemplateFiles() {
	local templateDirectory=${1:?"ERROR:  A template directory must be provided as the first positional argument to ${FUNCNAME[0]}!"}
	local templateExtension=${2:?"ERROR:  A template extension must be provided as the second positional argument to ${FUNCNAME[0]}!"}
	local forceOverwrite=${3:-false}
	local preserveTemplateFiles=${4:-false}
	local templateFiles=$(find "$templateDirectory" -maxdepth 1 -type f -iname "*${templateExtension}*")
	local templateFile templateText concreteFile
	for templateFile in $templateFiles; do
		logVerbose "Processing ${templateFile}..."
		templateText=$(cat "$templateFile")
		if [ 0 -ne $? ]; then
			errorOut 2 "Unable to read ${templateFile}!"
		fi

		# Empty templates offer no value
		if [ -z "$templateText" ]; then
			logWarning "Template file, ${templateFile}, is empty!"
			continue
		fi

		# Remove the template extension from the file name
		concreteFile="${templateFile//${templateExtension}/}"
		if [ "$templateFile" == "$concreteFile" ]; then
			errorOut 4 "Concrete and template file names are identical:  ${templateFile}"
		fi
		if [ -e "$concreteFile" ] && ! $forceOverwrite; then
			errorOut 5 "Concrete file, ${concreteFile}, already exists!  Set --force to overwrite."
		fi

		# Perform variable substitution
		templateText=$(substituteTemplateVariables "$templateText")
		logDebug "Interpolated template text:"
		logDebug "$templateText"

		# Write the result to the concrete file and delete the template file
		logDebug "Saving interpolated template to ${concreteFile}..."
		echo "$templateText" >"$concreteFile"
		if [ 0 -ne $? ]; then
			errorOut 3 "Unable to write ${concreteFile}!"
		fi

		if ! $preserveTemplateFiles && ! rm -f "$templateFile"; then
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
for _templateDirectory in "${_templateDirectories[@]}"; do
	# Check whether the template directory exists and is a directory
	if [ ! -d "$_templateDirectory" ]; then
		logError "The template directory, ${_templateDirectory}, does not exist or is not a directory!"
		_hasErrors=true
		continue
	fi

	logVerbose "Processing template files in ${_templateDirectory} with extension ${_templateExtension}..."
	processTemplateFiles "$_templateDirectory" "$_templateExtension" $_forceOverwrite $_preserveTemplateFiles
done
if $_hasErrors; then
	errorOut 86 "Exiting with errors..."
fi
