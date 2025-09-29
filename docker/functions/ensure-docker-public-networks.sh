################################################################################
# Implement the ensureDockerPublicNetworks function.
#
# Copyright 2025 William W. Kimball, Jr., MBA, MSIS
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# Dynamically load the common logging functions; prefer STD_SHELL_LIB over
# any relative LIB_DIRECTORY.
if [ -z "$STD_SHELL_LIB" ]; then
	# Set LIB_DIRECTORY relative to this file's location within the library
	# hierarchy, but only when LIB_DIRECTORY is not already set.
	if [ -z "$LIB_DIRECTORY" ]; then
		# The common library directory is not set, so set it to the default
		# value relative to this file's location within the library hierarchy.
		MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
		PROJECT_DIRECTORY="$(cd "${MY_DIRECTORY}/../../../" && pwd)"
		LIB_DIRECTORY="${PROJECT_DIRECTORY}/lib"
		readonly MY_DIRECTORY PROJECT_DIRECTORY LIB_DIRECTORY
	fi
else
	# Let LIB_DIRECTORY be used in lieu of STD_SHELL_LIB when set
	if [ -z "$LIB_DIRECTORY" ]; then
		LIB_DIRECTORY="$STD_SHELL_LIB"
		readonly LIB_DIRECTORY
	fi
fi
setLoggerSource="${LIB_DIRECTORY}/logging/set-logger.sh"
if ! source "$setLoggerSource"; then
	echo "ERROR:  Unable to source ${setLoggerSource}!" >&2
	exit 2
fi
unset setLoggerSource

###
# Ensure all of a set of named public Docker networks exist.
#
# This function does not set subnets or gateway addresses.
#
# Arguments:
# @param networkName0 <string> The name of the first public Docker network.
# @param networkNameN <string> The name of the Nth public Docker network.
#
# Returns:
# @return <integer> One of:
#   0:  all networks exist
#   1:  at least one network name was empty
#   2:  at least one network creation failed
# STDOUT:  Output from the docker CLI commands
# STDERR:  Various error messages
##
function ensureDockerPublicNetworks {
	local networkNames=("$@")
	local returnState=0

	for networkName in "${networkNames[@]}"; do
		if [ -z "$networkName" ]; then
			logError "An empty network name was provided to ${FUNCNAME[0]}!"
			if [ 0 -eq $returnState ]; then
				returnState=1
			fi
			continue
		fi

		if ! docker network ls | grep -q "$networkName"; then
			logInfo "Creating missing public Docker (external Compose) network: $networkName"
			docker network create "$networkName" \
				--driver bridge
			if [ 0 -ne $? ]; then
				# 2 is worse than 1, so don't check for non-zero
				returnState=2
			fi
		fi
	done

	return $returnState
}
