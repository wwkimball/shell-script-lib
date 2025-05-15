#!/bin/bash
################################################################################
# Update the schema of a MySQL database.
#
# This script attempts to upgrade or downgrade a MySQL database schema by
# running discoverd Schema Description Files (DDL) in the a directory tree.  The
# files are run in alpha-numerical order, forward or reverse.  This script will
# automatically roll-back failed operations (provided a rollback file is
# available).
#
# When run live, the user can abort the operation by pressing Ctrl+C, triggering
# a full rollback of all Schema Description Files which had already run up to
# that point.
#
# This script can be integrated with Docker Compose to run against a local
# development environment.  This script can also run in non-development
# deployment stages where the database server runs on a remote server accessible
# via a network connection; the script will use the 'mysql' command to
# communicate with it.
#
# A mandatory settings table must exist in the database schema and it must be a
# key-value store with one entry used for tracking the schema version.  The
# particular name of the table and its columns can be set via command-line
# arguments.
#
# In order to deliberately downgrade a database schema, the --force (or -f) flag
# must be passed or an error will be thrown.  This is to prevent accidental data
# loss.
#
# Usage:
#   export MYSQL_PASSWORD='<Your admin password>'
#   ./postgresql.sh [target-version]
#   unset MYSQL_PASSWORD
#
# Example:  Just update the schema to the latest version
#   ./postgresql.sh
#
# Example:  Update the schema to a specific version
#   ./postgresql.sh 20250512-3
#
# Example:  Downgrade the schema to a specific version
#   ./postgresql.sh --force 20250510-1
#
# Example:  Destroy the schema and start over
#   ./postgresql.sh --force 00000000-0 && ./postgresql.sh
#
# Copyright 2025 William W. Kimball, Jr. MBA MSIS
################################################################################
# Constants
MY_VERSION='2025.05.09-1'
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIRECTORY="$(cd "${MY_DIRECTORY}/../../../" && pwd)"
LIB_DIRECTORY="${PROJECT_DIRECTORY}/lib"
DOCKER_DIRECTORY="${PROJECT_DIRECTORY}/docker"
COMPOSE_BASE_FILE="${DOCKER_DIRECTORY}/docker-compose.yaml"
DEPLOY_STAGE_DEVELOPMENT=development
DEPLOY_STAGE_LAB=lab
DEPLOY_STAGE_QA=qa
DEPLOY_STAGE_STAGING=staging
DEPLOY_STAGE_PRODUCTION=production
VERSION_NUMBER_MAX='99999999-99999999'
readonly MY_VERSION MY_DIRECTORY PROJECT_DIRECTORY LIB_DIRECTORY \
	DOCKER_DIRECTORY COMPOSE_BASE_FILE DEPLOY_STAGE_DEVELOPMENT \
	DEPLOY_STAGE_LAB DEPLOY_STAGE_QA DEPLOY_STAGE_STAGING \
	DEPLOY_STAGE_PRODUCTION VERSION_NUMBER_MAX

# Import the entire common shell script function library
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
	echo "ERROR:  Failed to import shell helpers!" >&2
	exit 2
fi

# Create a global array for tracking executed DDL files
declare -a _alreadyRunDDLs

# Process command-line arguments, when provided
_hasErrors=false
_bakedComposeFile=''
_databaseHost=${MYSQL_HOST:-database}
_databaseName=$MYSQL_DATABASE
_databasePassword=$MYSQL_PASSWORD
_databasePort=${MYSQL_PORT:-3306}
_databaseUser=${MYSQL_USER:-root}
_deployStage=$DEPLOY_STAGE_DEVELOPMENT
_ddlFileType=ddl
_ddlDir="${PROJECT_DIRECTORY}/${_ddlFileType}"
_ddlSuffix=.${_ddlFileType}
_forceRollback=false
_isDevelopmentStage=false
_rollbackSuffix=.rollback${_ddlSuffix}
_logLevel=${LOG_LEVEL:-"NORMAL"}
_passwordFile=''
_schemaSettingsTable=settings
_schemaVersionKey=schema_version
_settingsNameColumn=name
_settingsValueColumn=value
_targetVersion=$VERSION_NUMBER_MAX
_versionDBName="$_databaseName"
while [ $# -gt 0 ]; do
	case $1 in
		-a|--settings-value-column)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_settingsValueColumn=$2
				shift
			fi
			;;

		-b|--version-database)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_versionDBName=$2
				shift
			fi
			;;

		-D|--default-db-name)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_databaseName=$2
				shift
			fi
			;;

		-d|--stage)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				if [[ "$2" =~ ^[Dd] ]]; then
					_deployStage=$DEPLOY_STAGE_DEVELOPMENT
					_pushImages=false
				elif [[ "$2" =~ ^[Ll] ]]; then
					_deployStage=$DEPLOY_STAGE_LAB
				elif [[ "$2" =~ ^[Qq] ]]; then
					_deployStage=$DEPLOY_STAGE_QA
				elif [[ "$2" =~ ^[Ss] ]]; then
					_deployStage=$DEPLOY_STAGE_STAGING
				elif [[ "$2" =~ ^[Pp] ]]; then
					_deployStage=$DEPLOY_STAGE_PRODUCTION
				else
					logError "Unsupported value, ${2}, for $1 option."
					_hasErrors=true
				fi
				shift
			fi
			;;

		-f|--force)
			_forceRollback=true
			;;

		-h|--db-host)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_databaseHost=$2
				shift
			fi
			;;

		--help)
			cat <<EOHELP
$0 [OPTIONS] [--] [TARGET_SCHEMA_VERSION]

Update the database schema.  OPTIONS include:
  --
    The double hyphen is an optional, explicit end-of-options marker.  It is
    usually only necessary only when the first non-option positional argument to
    a command starts with a hyphen (-).  Since TARGET_SCHEMA_VERSION never will,
    it is included here for conformity with shell command norms.
  -a SETTINGS_VALUE_COLUMN, --settings-value-column SETTINGS_VALUE_COLUMN
    The name of the column in SETTINGS_TABLE containing the setting value.
    The default is, ${_settingsValueColumn}.
  -b SETTINGS_DB_NAME, --version-database SETTINGS_DB_NAME
    The name of the database containing the SETTINGS_TABLE.  This is usually the
    same as the database containing the target schema but it does not need to be
    as long as your Schema Description Files create/manage both.  The default
    value can be controlled by setting the MYSQL_DATABASE environment variable.
    The present default is, ${_versionDBName}.
  -D DEFAULT_DATABASE, --default-db-name DEFAULT_DATABASE
    The default name of the database to run the Schema Description Files against
    whenever any are found lacking the optional database header line.  It is
    used only when the header is missing from a Schema Description File.  This
    is usually the same as the database containing the SETTINGS_TABLE but it
    does not need to be as long as your Schema Description Files create/manage
    it, too.  The default value can be controlled by setting the MYSQL_DATABASE
    environment variable.  The present default is, ${_databaseName}.
  -d DEPLOY_STAGE, --stage DEPLOY_STAGE
    Indicate which deployment stage to run against.  This controls which
    Docker Compose override file is used based on the presence of the
    DEPLOY_STAGE string within the file name matching the pattern:
    docker-compose.DEPLOY_STAGE.yaml.  Must be one of:
      * ${DEPLOY_STAGE_DEVELOPMENT}
      * ${DEPLOY_STAGE_LAB}
      * ${DEPLOY_STAGE_QA}
      * ${DEPLOY_STAGE_STAGING}
      * ${DEPLOY_STAGE_PRODUCTION}
    The default is ${_deployStage}.
  -f, --force
    Force a rollback of the present schema version to the target schema
    version.  Without this set, the script will throw an error when the
    present schema version is greater than TARGET_SCHEMA_VERSION in order to
    prevent unintended data loss.
  -h DATABASE_HOST, --db-host DATABASE_HOST
    The hostname of the MySQL database server.  Can be set to the name of the
    local (development) Docker Compose service to use for the database.  The
    default can be controlled by setting the MYSQL_HOST environment variable.
    The present default value is, ${_databaseHost}.
  --help
    Display this help message and exit.
  -k VERSION_KEY, --version-key VERSION_KEY
    The name of the key in SETTINGS_TABLE containing the schema version.
    The default is, ${_schemaVersionKey}.
  -l DDL_DIRECTORY, --ddl-directory DDL_DIRECTORY
    The directory containing the DDL files to run.  The files can be
    organized into subdirectories, usually in a structure like ./YYYY/MM/*.
    See Schema Version Rules for additional information.  The default is,
    ${_ddlDir}.
  -n SETTINGS_NAME_COLUMN, --settings-name-column SETTINGS_NAME_COLUMN
    The name of the column in SETTINGS_TABLE containing the setting name.
    The default is, ${_settingsNameColumn}.
  -P, --password-file
    The path to a file containing the password for the DATABASE_USER (able to
    create other databases, users, hosts, and so on).  Set this when you'd
    rather not -- or cannot -- set the MYSQL_PASSWORD environment variable.
  -p DATABASE_PORT, --db-port DATABASE_PORT
    The port number via which the database can be accessed.  The default can be
    controlled by setting the MYSQL_PORT environment variable.  The present
    default is, ${_databasePort}.
  -s SETTINGS_TABLE, --settings-table SETTINGS_TABLE
    The name of the table containing the schema version.  The default
    is, ${_schemaSettingsTable}.
  -u DATABASE_USER, --db-user DATABASE_USER
    The name of the superadmin user who can manage the target database server
    and update the schema version in SETTINGS_DB_NAME.  The default can be
    controlled by setting the MYSQL_USER environment variable.  The present
    default is, ${_databaseUser}.
  -v, --verbose
    Enable verbose logging.  This option may be specified up to twice to
    increase verbosity from verbose to debug.
  --version
    Display the version of this script and exit.
  -x DDL_EXTENSION, --ddl-extension DDL_EXTENSION
    The filename extension of the DDL files to run.  This is typically "ddl"
    or "sql".  Setting this value also controls the roll-back file extension
    using pattern ".rollback.DDL_EXTENSION".  The default is,
    ${_ddlFileType}.

  TARGET_SCHEMA_VERSION
    The target schema version to update to.  When not provided, the script
    will run all DDL files from the present schema version to the highest
    available schema version.  The schema version given must be valid or an
    error will be thrown.  The default is, ${_targetVersion}.  See Schema
    Version Rules for information about how to format this value.

Schema Version Rules:
  The TARGET_SCHEMA_VERSION argument and all provided schema description files
  must follow the same value and naming rules.  Files are named for the schema
  version they represent.  The schema version must be in the format,
  YYYYMMDD-N, where YYYY is the year, MM is the month, DD is the day, and
  N is a sequence number (enabling multiple files to have been created on
  the same day).  The whole number is used to sort the schema description
  files.

  The SETTINGS_TABLE must be designed as a key-value store with the following
  columns:
    SETTINGS_NAME_COLUMN
      The name of the setting.  This must be a unique-constrained column.
    SETTINGS_VALUE_COLUMN
      The value of the setting.

Schema Description Files:
  Each schema description file may contain a commented header block with the
  following keys in the following format.  Note that the header block must be
  the first, uninterrupted lines of the file.  The required format is:

  -- Any other commented header lines, or none
  -- database:  TARGET_DATABASE_NAME
  -- Any other trailing header lines, or none

  WHERE:
    * TARGET_DATABASE_NAME
      The name of the database against which the contents of the file will be
      run.  The default is the final value of SETTINGS_DB_NAME.  Note that the
      resultant schema version will still be written to SETTINGS_TABLE in
      SETTINGS_DB_NAME.

Disclaimer:
  This script is destructive and can tear down a production database!  You take
  on full and personal responsibility for running this script.  The author and
  maintainer(s) of this script are not responsible for any data loss or
  corruption that may occur as a result of doing so.  You are strongly advised
  to create a full backup of the target database(s) before using this!

EOHELP
			exit 0
			;;

		-k|--version-key)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_schemaVersionKey=$2
				shift
			fi
			;;

		-l|--ddl-directory)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_ddlDir=$2
				shift
			fi
			;;

		-n|--settings-name-column)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_settingsNameColumn=$2
				shift
			fi
			;;

		-P|--password-file)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_passwordFile=$2
				shift

				# Ensure the file exists
				if [ ! -f "$_passwordFile" ]; then
					logError "File not found:  $_passwordFile"
					_hasErrors=true
				else
					# Read the password from the file
					_databasePassword=$(head -1 "$_passwordFile")
				fi
			fi
			;;

		-p|--db-port)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_databasePort=$2
				shift
			fi
			;;

		-s|--settings-table)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_schemaSettingsTable=$2
				shift
			fi
			;;

		-u|--db-user)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_databaseUser=$2
				shift
			fi
			;;

		-v|--verbose)
			# Increase the verbosity of output logging
			case $_logLevel in
				VERBOSE)
					# VERBOSE becomes DEBUG; ignore anything else
					_logLevel="DEBUG"
					;;
				DEBUG)
					# There is no level higher than DEBUG
					_logLevel="DEBUG"
					;;
				*)
					# Any other level becomes VERBOSE
					_logLevel="VERBOSE"
					;;
			esac
			;;

		--version)
			logLine "$0 version, ${MY_VERSION}."
			exit 0
			;;

		-x|--ddl-extension)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_ddlFileType=$2

				# Remove any leading dots (.) from the argument value
				_ddlFileType=${_ddlFileType#.}

				# The resulting value cannot be empty
				if [ -z "$_ddlFileType" ]; then
					logError "Invalid value for $1 option!"
					_hasErrors=true
				fi

				# Derive other values from the DDL file type
				_ddlSuffix=.${_ddlFileType}
				_rollbackSuffix=.rollback${_ddlSuffix}
				shift
			fi
			;;

		--) # Explicit end of options
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

# TARGET_SCHEMA_VERSION must be set or omitted
if [ $# -gt 1 ]; then
	logError "Too many positional arguments.  See --help for more information."
	_hasErrors=true
fi
_targetVersion=${1:-$VERSION_NUMBER_MAX}

# Validate TARGET_SCHEMA_VERSION
if [[ ! "$_targetVersion" =~ ^[[:digit:]]{8}-[[:digit:]]+$ ]]; then
	logError "Invalid TARGET_SCHEMA_VERSION, $_targetVersion.  See --help for more information."
	_hasErrors=true
fi

# Identify whether the script is running in a development deployment stage
if [ $_deployStage == $DEPLOY_STAGE_DEVELOPMENT ] && [ -f "$COMPOSE_BASE_FILE" ]; then
	_isDevelopmentStage=true
fi

# All database connection parameters must be set
declare -A _requiredParams=(
	["user"]=$_databaseUser
	["host"]=$_databaseHost
	["port"]=$_databasePort
	["password"]=$_databasePassword
	["name"]=$_databaseName
)
for _requiredParam in "${!_requiredParams[@]}"; do
	if [ -z "${_requiredParams[$_requiredParam]}" ]; then
		logError "A database $_requiredParam must be specified!  See --help for more information."
		_hasErrors=true
	fi
done

# Additional checks based on whether the script is running against a development
# deployment stage.
if $_isDevelopmentStage; then
	# Verify Docker is running
	if ! docker info >/dev/null 2>&1; then
		logError "Docker is not running!"
		_hasErrors=true
	fi

	# Verify Docker Compose is installed
	if ! docker compose --version >/dev/null 2>&1; then
		logError "Docker Compose is not installed!"
		_hasErrors=true
	fi

	# yamlpath (and Python 3) is required to parse Docker Compose files
	if ! yaml-get --version &>/dev/null; then
		logError "yamlpath (https://github.com/wwkimball/yamlpath?tab=readme-ov-file#installing) is not installed!"
		_hasErrors=true
	fi

	# Attempt to bake the configuration file
	_bakedComposeFile=$(mktemp)
	trap "rm -f $_bakedComposeFile" EXIT
	if ! dynamicBakeComposeFile "$_bakedComposeFile" "$_deployStage" "$DOCKER_DIRECTORY"
	then
		logError "Unable to bake ${COMPOSE_BASE_FILE}."
		_hasErrors=true
	fi
fi

# Present debugging information
logDebug "$(cat <<-EODEBUG
  You are running script, ${0}, version, ${MY_VERSION}.
  -
            Deployment stage:  ${_deployStage}
  Is development environment:  ${_isDevelopmentStage}
  -
               Schema settings table:  ${_schemaSettingsTable}
   Schema settings table name column:  ${_settingsNameColumn}
  Schema settings table value column:  ${_settingsValueColumn}
                  Schema version key:  ${_schemaVersionKey}
  -
      Database Host:  ${MYSQL_HOST}
      Database Port:  ${MYSQL_PORT}
      Database Name:  ${MYSQL_DATABASE}
      Database user:  ${MYSQL_USER}
  Database Password:  <HIDDEN>
EODEBUG
)"

# Bail when there are errors
if $_hasErrors; then
	exit 1
fi

###
# Transparently pass arguments to mysql.
#
# This can be run either against a local development container or a remote
# database server.  The result code and STDOUT/STDERR output are from mysql.
##
function executeSQL {
	# Transparently pass all arguments through to mysql
	if $_isDevelopmentStage; then
		# Use a Docker Compose command to execute the command against the local
		# development container
		dockerCompose "$_bakedComposeFile" "" \
			--profile "$_deployStage" \
			exec -T "$_databaseHost" \
			mysql "$@"
	else
		mysql \
			--host="$_databaseHost" \
			--port="$_databasePort" \
			--user="$_databaseUser" \
			--password="$_databasePassword" \
			"$@"
	fi
}

###
# Get the present schema version from the database.
#
# @return <integer> 0 on success; non-zero on failure:
#   * 2:  The present schema version could not be determined; the error message
#         is printed to STDERR.
# @return <string> The present schema version, when known; empty otherwise.
##
function getPresentSchemaVersion {
	# Get the present schema version
	local sqlQuery="SELECT ${_settingsValueColumn} FROM ${_schemaSettingsTable} WHERE ${_settingsNameColumn} = '${_schemaVersionKey}';"
	local presentVersion=$(executeSQL \
		--database="$_versionDBName" \
		--user="$_databaseUser" \
		--skip-column-names \
		--silent \
		--raw \
		--batch \
		--execute="$sqlQuery" \
		2>&1 \
	)
	local commandExitCode=$?

	# When the present schema version cannot be found, determine the cause of the
	# error.  When the cause is that the schema does not exist, then all DDL
	# files will be run.  While not perfectly safe, also assume the version is
	# zero (0) whenever the settings table does not exist.  If the cause is
	# anything else, the script will exit with an error.
	if [ $commandExitCode -ne 0 ] || [[ ! "$presentVersion" =~ ^[0-9]{8}\-[0-9]+$ ]]; then
		if [[ $presentVersion =~ "database "\"[[:alnum:]]+\"" does not exist"$ ]]; then
			# The database schema does not exist
			presentVersion="00000001-0"	# One higher than minimum version
		elif [[ $presentVersion == *"relation \"${_schemaSettingsTable}\" does not exist"* ]]; then
			# The database schema exists but not the required settings table
			presentVersion="00000001-0"	# One higher than minimum version
		else
			# Unanticipated error
			logError "Unable to determine present schema version due to error:  ${presentVersion}."
			return 2
		fi
	fi

	# Return the present schema version
	echo "$presentVersion"
}

###
# Set the schema version in the settings table.
#
# @param <string> $1 The schema version to set.
#
# @return <integer> 0 on success; non-zero on failure.  While this value is
#         primarily from the mysql command, this function will also return 1 when
#         the schema version is not valid.
##
function setSchemaVersion {
	local schemaVersion=${1:?"ERROR:  Schema version is required as the first positional argument to ${FUNCNAME[0]}."}

	# The supplied version number must be valid
	if [[ ! "$schemaVersion" =~ ^[0-9]{8}\-[0-9]+$ ]]; then
		logError "Attempt to set schema version to invalid value:  ${schemaVersion}"
		return 1
	fi

	# Set the schema version
	local sqlStatement="UPDATE ${_schemaSettingsTable} SET ${_settingsValueColumn} = '${schemaVersion}' WHERE ${_settingsNameColumn} = '${_schemaVersionKey}';"
	local commandOutput	# Declare locals without assignment to detect errors
	commandOutput=$(executeSQL \
		--database="$_versionDBName" \
		--user="$_databaseUser" \
		--skip-column-names \
		--silent \
		--raw \
		--batch \
		--execute="$sqlStatement" \
		2>&1 \
	)
	local commandExitCode=$?

	# Ignore errors related to missing database schema or settings table; the
	# user-supplied script(s) will be run to create them.
	if [ $commandExitCode -ne 0 ]; then
		if [[ $commandOutput =~ "database "\"[[:alnum:]]+\"" does not exist"$ ]]; then
			commandExitCode=0
			logWarning "Unable to set database schema version to, ${schemaVersion}, because the database does not exist."
		elif [[ $commandOutput == *"relation \"${_schemaSettingsTable}\" does not exist"* ]]; then
			commandExitCode=0
			logWarning "Unable to set database schema version to, ${schemaVersion}, because the ${_schemaSettingsTable} table does not exist."
		else
			logError "Unable to set database schema version due to error:  ${commandOutput}."
		fi
	fi

	# Return the command exit code
	return $commandExitCode
}

###
# Run a DDL file.
#
# A transaction will be wrapped around the content of the DDL file.  Should the
# transaction fail, the DDL file will be run "bare" (without the transaction
# wrapper).  All executed DDL files are tracked for potential rollback.
#
# An optional second argument can be provided to indicate that the DDL file is
# being run for rollback purposes and should not itself be tracked for rollback.
#
# The DDL filename must be in the format YYYYMMDD-N.DDL_EXTENSION.  The whole
# number is used to update the schema version in the SETTINGS_TABLE table.
#
# @param <string> $1 The DDL file to run.
# @param <string> $2 (optional) Must be unset, empty, or "for-rollback"
#
# @return <integer> 0 on success; non-zero on failure.  In most cases, the exit
#         code from the mysql command will be returned.  However, when the schema
#         version cannot be set in SETTINGS_TABLE, the function will return
#         100.
# @return via STDOUT <string> Various infomrative messages.
# @return via STDERR <string> An error message if an error occurred.
##
function runDDLFile {
	# Get the DDL file name from the first argument
	local ddlFile=${1:?"ERROR:  DDL file name is required."}
	local trackExecution=true
	if [ ! -z "$2" ] && [ $2 == "for-rollback" ]; then
		trackExecution=false
	fi

	# Get the schema version from the DDL file name
	local ddlVersion=$(basename $ddlFile "$_rollbackSuffix")
	ddlVersion=$(basename $ddlVersion "$_ddlSuffix")

	# Add the version update to the DDL file, all within a transaction, using
	# a temporary file.  The temporary file is used so that the original DDL
	# file is not modified and so that the combined commands can be piped into
	# mysql.
	local tmpFile=$(mktemp)
	cat >"$tmpFile" <<-EOTRANSACTION
		BEGIN;
		$(cat "$ddlFile")
		UPDATE ${_schemaSettingsTable} SET ${_settingsValueColumn} = '${ddlVersion}' WHERE ${_settingsNameColumn} = '${_schemaVersionKey}';
		COMMIT;
EOTRANSACTION

	# The database name to run against is stored in the DDL file as a
	# comment in the header of the file.  It can be on any line before the
	# first non-commented line.
	local databaseName=$(grep -m 1 -E "^--\s*[Dd]atabase:\s*[[:alnum:]_]+$" "$ddlFile" | cut -d: -f2 | tr -d '[:space:]')
	if [ -z "$databaseName" ]; then
		logWarning "Database name header not found in Schema Description File, ${ddlFile}.  Using ${_databaseName}."
		databaseName=$_databaseName
	fi

	# Run the DDL file
	logVerbose "Running Schema Description File, ${ddlFile}, against database, ${databaseName}."
	local commandOutput	# Declare locals without assignment to detect errors
	commandOutput=$(cat "$tmpFile" | executeSQL \
		-U "$_databaseUser" \
		-d "$databaseName" 2>&1 \
	)
	local commandExitCode=$?

	if [ $commandExitCode -eq 0 ]; then
		# Add the DDL file to the list of already-run DDL files
		if $trackExecution; then
			_alreadyRunDDLs+=("$ddlFile")
		fi
		logVerbose "Transaction-based execution of ${ddlFile} was successful."
	else
		# Check the command output for a message indicating that the DDL file
		# cannot be run in a transaction.  If so, then run the DDL file
		# without a transaction.
		if [[ "$commandOutput" =~ "cannot run inside a transaction block"$ ]]; then
			logWarning "The transaction failed because the Schema Description File contains at least one command which cannot be run inside a transaction."
			logInfo "Re-running Schema Description File, ${ddlFile}, without a transaction against database, ${databaseName}."
			cat "$ddlFile" | executeSQL \
				--batch \
				--user="$_databaseUser" \
				--database="$databaseName"
			commandExitCode=$?

			if [ $commandExitCode -eq 0 ]; then
				# Add the DDL file to the list of already-run DDL files
				if $trackExecution; then
					_alreadyRunDDLs+=("$ddlFile")
				fi
				if ! setSchemaVersion $ddlVersion; then
					return 100
				fi
			else
				logError "Schema Description File, ${ddlFile}, failed against database, ${databaseName}."
			fi

		# Warn when the settings table does not exist and rerun the DDL file
		# without the version update.
		elif [[ "$commandOutput" == *"relation \"${_schemaSettingsTable}\" does not exist"* ]]; then
			logWarning "The transaction failed because the ${_schemaSettingsTable} table does not exist."
			logInfo "Re-running Schema Description File, ${ddlFile}, without the version update against database, ${databaseName}."
			cat "$ddlFile" | executeSQL \
				-v ON_ERROR_STOP=ON \
				-U "$_databaseUser" \
				-d "$databaseName"
			commandExitCode=$?

			if [ $commandExitCode -eq 0 ]; then
				# Add the DDL file to the list of already-run DDL files
				if $trackExecution; then
					_alreadyRunDDLs+=("$ddlFile")
				fi
				if ! setSchemaVersion $ddlVersion; then
					return 101
				fi
			else
				logError "Schema Description File, ${ddlFile}, failed against database, ${databaseName}."
			fi
		else
			# Indicate that the DDL file failed to run
			logError "$commandOutput"
			logError "Schema Description File, ${ddlFile}, failed against database, ${databaseName}."
		fi
	fi

	# Remove the temporary file
	rm "$tmpFile"

	# Return the command exit code
	return $commandExitCode
}

###
# Report the final schema version.
##
function reportFinalSchemaVersion {
	# Get the present schema version
	local presentVersion=$(getPresentSchemaVersion)

	# Report the final schema version
	logCharLine "="
	logInfo "Finished with the database schema at version, ${presentVersion}."
}

###
# Rollback all already-run DDL files in reverse order.
#
# This function will be called when the script process receives a SIGINT signal.
# This is typically generated when the user presses Ctrl+C while this script is
# running.  This operation goes in both directions; it can rollback both forward
# and rollback DDL files.  This determination is made on a file-by-file basis.
#
# The global array, _alreadyRunDDLs, is populated elsewhere in this script.  Its
# contents are iterated in reverse order to rollback the DDL files.  Any error
# encountered while rolling back a DDL file will be reported and is fatal.
##
function rollbackDDLsOnInterrupt {
	logCharLine "#"
	logWarning "Received SIGINT signal; rolling back all already-run Schema Description Files."

	# If there are no already-run DDL files, then exit cleanly.
	if [ ${#_alreadyRunDDLs[@]} -eq 0 ]; then
		logInfo "No Schema Description Files to rollback."
		reportFinalSchemaVersion
		exit 0
	fi

	local i ddlFile removeSuffix addSuffix rollbackDDLFile

	# Rollback the already-run DDL files in reverse order as stored in the
	# _alreadyRunDDLs array.
	logInfo "Rolling back Schema Description Files that have already been executed."
	for ((i=${#_alreadyRunDDLs[@]}-1; i>=0; i--)); do
		ddlFile=${_alreadyRunDDLs[$i]}

		# Invert the DDL file suffixes; if it is a forward DDL file, then
		# swap .ddl for .rollback.ddl and vice versa.
		if [[ "$ddlFile" =~ $_rollbackSuffix$ ]]; then
			removeSuffix=$_rollbackSuffix
			addSuffix=$_ddlSuffix
		else
			removeSuffix=$_ddlSuffix
			addSuffix=$_rollbackSuffix
		fi
		rollbackDDLFile=$(basename "$ddlFile" "$removeSuffix")${addSuffix}

		# Run the rollback DDL file
		runDDLFile "$rollbackDDLFile" for-rollback
		if [ $? -eq 0 ]; then
			logVerbose "Rolled back Schema Description File, ${ddlFile}."
		else
			errorOut 4 "Error running rollback Schema Description File, ${rollbackDDLFile}."
		fi
	done
	exit 0
}
trap rollbackDDLsOnInterrupt SIGINT

# Get the present schema version
presentVersion=$(getPresentSchemaVersion)
if [ $? -ne 0 ]; then
	exit 2
fi

# For version number comparisons, the dash in the schema version is changed to
# a period so that the version can be compared as a floating point number.
dotPresentVersion=${presentVersion//-/.}
dotTargetVersion=${_targetVersion//-/.}
compareFloats "$dotPresentVersion" "$dotTargetVersion"
versionComparison=$?

# Present debugging information on request
logDebug "$(cat <<-EODEBUG
  Present schema version:  ${presentVersion}
  Dotted present version:  ${dotPresentVersion}
  -
  Target schema version:  ${_targetVersion}
  Dotted target version:  ${dotTargetVersion}
  -
  Version comparison:  ${versionComparison}
EODEBUG
)"

# If the present schema version is the same as the target schema version to
# run, then exit as finished.
if [ $versionComparison -eq 2 ]; then
	logInfo "There is nothing to do; the present version is already the same or greater than the target."
elif [ $versionComparison -eq 3 ]; then
	# If the present schema version is greater than the target schema version to
	# run, then this is a deliberate rollback action and _forceRollback must be set.
	# For this comparision, the dash in the schema version is changed to a period
	# so that the version can be compared as a floating point number.
	# A rollback action must be deliberate, so _forceRollback must be set
	if ! $_forceRollback; then
		errorOut 1 "To rollback the database schema, you must set --force (or -f)."
	fi

	# Find all DDL files from the present schema version to the lower target
	# schema version to run and run them in reverse order.
	logInfo "Rolling back database schema from version, ${presentVersion}, to version, ${_targetVersion}."
	for ddlFile in $(find "$_ddlDir" -type f -iname "*${_rollbackSuffix}" | sort -r); do
		# Get the schema version from the DDL file name
		ddlVersion=$(basename $ddlFile "$_rollbackSuffix")
		dotDDLVersion=${ddlVersion//-/.}
		dotNextLowerVersion=$(decrementDottedVersion "$dotDDLVersion")
		nextLowerVersion=${dotNextLowerVersion//./-}

		# Compare the version numbers
		compareFloats "$dotDDLVersion" "$dotPresentVersion"
		compareToPresent=$?
		compareFloats "$dotDDLVersion" "$dotTargetVersion"
		compareToTarget=$?

		# Ignore files that have higher versions than the present schema
		# because they have not yet been run against the database.
		if [ $compareToPresent -eq 3 ]; then
			continue
		fi

		# Stop when the DDL file version is less than or equal to the target
		# schema version to run.
		if [ $compareToTarget -le 2 ]; then
			logVerbose "Stopping at Schema Description File, ${ddlFile}, because it has a lower or equal version than the target schema version, ${_targetVersion}."

			# Set the schema version to the target version
			if ! setSchemaVersion "$_targetVersion"; then
				exit 8
			fi
			break
		fi

		# Run the DDL file
		runDDLFile "$ddlFile"
		if [ $? -eq 0 ]; then
			logVerbose "Rolled back database schema to version, ${presentVersion}; attempting to set the database schema version to ${nextLowerVersion} from ${dotNextLowerVersion} based on ${dotDDLVersion}..."
		else
			exit 5
		fi

		# At this time, the schema version setting is incorrect because it now
		# shows the version number of the rollback DDL file that was just run.
		# To fix this, the schema version setting must be updated to the
		# next lower version number.  The settings table and even the database
		# may not exist, so be tolerant of those errors.
		if ! setSchemaVersion "$nextLowerVersion"; then
			exit 8
		fi
	done
elif [ $versionComparison -eq 1 ]; then
	# If the present schema version is less than the target schema version to
	# run, then run the DDL files in the db/ddl directory in alpha-numerical
	# order.
	if [ "$_targetVersion" == "$VERSION_NUMBER_MAX" ]; then
		logInfo "Upgrading database schema from version, ${presentVersion}, to the highest available Schema Description File."
	else
		logInfo "Upgrading database schema from version, ${presentVersion}, to version, ${_targetVersion}."
	fi

	for ddlFile in $(find "$_ddlDir" -type f -iname "*${_ddlSuffix}" -not -iname "*${_rollbackSuffix}" | sort); do
		# Get the schema version from the DDL file name
		ddlVersion=$(basename $ddlFile "$_ddlSuffix")
		dotDDLVersion=${ddlVersion//-/.}

		# Compare the version numbers
		compareFloats "$dotDDLVersion" "$dotPresentVersion"
		compareToPresent=$?
		compareFloats "$dotDDLVersion" "$dotTargetVersion"
		compareToTarget=$?

		# Ignore files that have the same or lower versions than the present
		# schema because they have already been run against the database.
		if [ $compareToPresent -le 2 ]; then
			continue
		fi

		# Stop when the DDL file version is greater than or equal to the target
		# schema version to run.
		if [ $compareToTarget -eq 3 ]; then
			logVerbose "Stopping at Schema Description File, ${ddlFile}, because it has a higher or equal version than the target schema version, ${_targetVersion}."
			break
		fi

		# Run the DDL file
		runDDLFile "$ddlFile"
		if [ $? -ne 0 ]; then
			exit 6
		fi
	done
fi

reportFinalSchemaVersion
