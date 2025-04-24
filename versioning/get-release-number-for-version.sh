###############################################################################
# Defines a function, getReleaseNumberForVersion, which provides logic that can
# calculate the next release number for a given version number.  Tracking data
# is stored in a tab-delimited file, which is created if it does not exist.
#
# External configuration:
# - VERSION_DATA_DIR:  <string>  The base directory to use for storing version
#   tracking data.  The default value is "${HOME}/.data/release-versions".
#
# Copyright 2001, 2018 William W. Kimball, Jr. MBA MSIS
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# Constants
DEFAULT_VERSION_DATA_DIR=${VERSION_DATA_DIR:-"${HOME}/.data/release-versions"}
readonly DEFAULT_VERSION_DATA_DIR

# Dynamically load other components of the shell library
if [ -z "$LIB_DIRECTORY" ]; then
	MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	LIB_DIRECTORY="${MY_DIRECTORY}/lib"
	readonly MY_DIRECTORY LIB_DIRECTORY
fi
if ! source "${LIB_DIRECTORY}/logging/set-logger.sh"; then
	echo "ERROR:  Unable to source ${MY_DIRECTORY}/logging/set-logger.sh" >&2
	exit 2
fi

################################################################################
# Get the release number for a given version number.
#
# Based on the version number, this function will either increment the release
# number for the version number or create a new record for the version number.
#
# @param string $1 The product name to get the release number for.
# @param string $2 The version number to get the release number for.
# @param string $3 (OPTIONAL) The base data directory to use.  Can be set via
#				   the VERSION_DATA_DIR environment variable.
#
# @return STDOUT integer The release number for the given version number.
# @return STDERR string  An error message if the release number could not be
#                        determined.
# @return integer         0 The release number was successfully determined.
# @return integer         1 Any argument was not provided.
# @return integer        70 The base data directory could not be created.
# @return integer        71 The incremented release number could not be saved.
# @return integer        72 The other release records could not be copied.
# @return integer        73 The new version record could not be added.
# @return integer        74 The previous records could not be copied.
# @return integer        75 The old data file could not be removed.
# @return integer        76 The updated data file could not be saved.
# @return integer        77 The original data file could not be created.
#
# Modified and used with permission from William W. Kimball, Jr. MBA MSIS.
#
# Copyright 2001, 2018, 2024 William W. Kimball, Jr. MBA MSIS
#
# @see https://github.com/wwkimball/dynamic-package-builder/blob/master/contrib/func-get-release-number-for-version.sh
################################################################################
function getReleaseNumberForVersion {
	local productName=${1:?"ERROR:  A product name must be provided as the first positional argument to ${FUNCNAME[0]}."}
	local versionNumber=${2:?"ERROR:  A version number must be provided as the second positional argument to ${FUNCNAME[0]}."}
	local baseDataDirectory=${3:-$DEFAULT_VERSION_DATA_DIR}
	local buildArchitecture=$(uname -m)
	local dataFileDir="${baseDataDirectory}/${buildArchitecture}"
	local dataFileBaseName="${dataFileDir}/${productName}"
	local dataFile="${dataFileBaseName}.tab"
	local swapFile="${dataFileBaseName}.swap"
	local releaseNumber=1
	local versionRecord recVersion recCreated recModified rowCount

	# Check that the data directory can be utilized
	if [ ! -d "$dataFileDir" ]; then
		if ! mkdir -p "$dataFileDir"; then
			logError "Unable to create data storage directory, ${dataFileDir}"
			return 70
		fi
	fi

	if [ -f "$dataFile" ]; then
		versionRecord=$(grep "^${versionNumber}"$'\t' "${dataFile}")
		if [ 0 -eq $? ]; then
			IFS=$'\t' read -r recVersion releaseNumber recCreated recModified <<<"$versionRecord"
			((releaseNumber++))

			if ! echo -e "${recVersion}\t${releaseNumber}\t${recCreated}\t$(date)" >"$swapFile"
			then
				logError "Unable to save incremented release number to swap file, ${swapFile}."
				return 71
			fi

			# Don't bother copying zero rows
			rowCount=$(wc -l ${dataFile} | cut -d' ' -f1)
			if [ 1 -lt $rowCount ]; then
				if ! grep -v "^${recVersion}"$'\t' "$dataFile" >>"$swapFile"; then
					logError "Unable to copy other release records to swap file, ${swapFile}."
					return 72
				fi
			fi
		else
			if ! echo -e "${versionNumber}\t${releaseNumber}\t$(date)\t$(date)" >"$swapFile"
			then
				logError "Unable to add a new version record to swap file, ${swapFile}."
				return 73
			fi

			if ! cat "$dataFile" >>"$swapFile"; then
				logError "Unable to transfer previous records from ${dataFile} to a swap file, ${swapFile}."
				return 74
			fi
		fi

		if ! rm -f "$dataFile"; then
			logError "Unable to remove old data file, ${dataFile}."
			return 75
		fi
		if ! mv "$swapFile" "$dataFile"; then
			logError "Unable to save updated data file, ${swapFile}, to ${dataFile}."
			return 76
		fi
	else
		if ! echo -e "${versionNumber}\t${releaseNumber}\t$(date)\t$(date)" >"$dataFile"; then
			logError "Unable to create original data file, ${dataFile}."
			return 77
		fi
	fi

	echo "$releaseNumber"
}
