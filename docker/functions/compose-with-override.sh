################################################################################
# Implement the dockerCompose function.
#
# Copyright 2021, 2024, 2025 William W. Kimball, Jr., MBA, MSIS
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

###
# Run the docker compose command with the base and optional override file.
#
# @param string $1 The base Docker Compose file.
# @param string $2 The optional override Docker Compose file.
# @param string $@ The remaining arguments to Docker Compose.
#
# @return integer The exit code from Docker Compose.
##
function dockerCompose() {
	local mainComposeFile envComposeFile exitCode
	mainComposeFile=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file."}
	envComposeFile=$2
	shift 2
	exitCode=0

	if [ ! -z "$envComposeFile" -a -f "$envComposeFile" ]; then
		docker compose -f "$mainComposeFile" -f "$envComposeFile" "$@"
		exitCode=$?
	else
		docker compose -f "$mainComposeFile" "$@"
		exitCode=$?
	fi

	return $exitCode
}
