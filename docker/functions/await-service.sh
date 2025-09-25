################################################################################
# Implement the awaitService function.
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
# Define a function which waits for a named Docker Compose service to be ready.
#
# @param string $1 The profile name; one of development, lab, qa, staging, or
#                  production.
# @param string $2 The name of the service to wait for.
# @param string $3 The base Docker Compose file.
# @param string $4 The optional override Docker Compose file.
# @param string $5 The command to run in the service to check for readiness.
# @param string $6 The string to check for in the output of the command.
# @param integer $7 The maximum number of seconds to wait for the service.
# @param integer $8 The maximum number of errors to allow before giving up.
#
# @return integer 0 if the service became ready, 1 if it timed out, or 2 if it
#                 failed too many times.
##
function awaitService() {
	local profileName serviceName mainComposeFile envComposeFile readyCommand \
		readyCheck maximumWaitSeconds maximumErrors tempFile waitedSeconds \
		seenErrors returnState
	profileName=${1:?"ERROR:  ${FUNCNAME[0]}:  Missing profile name."}
	serviceName=${2:?"ERROR:  ${FUNCNAME[0]}:  Missing service name."}
	mainComposeFile=${3:?"ERROR:  ${FUNCNAME[0]}:  Missing base Docker Compose file."}
	envComposeFile=$4
	readyCommand=${5:-"echo 'ready'"}
	readyCheck=${6:-"ready"}
	maximumWaitSeconds=${7:-10}
	maximumErrors=${8:-5}

	# Use a temp file to check for errors from the service
	tempFile=$(mktemp)
	waitedSeconds=0
	seenErrors=0
	returnState=0
	trap "rm -f '$tempFile'" EXIT

	echo
	echo "Waiting for ${serviceName} to become ready..."
	while ! dockerCompose "$mainComposeFile" "$envComposeFile" \
		--profile "$profileName" \
		exec "$serviceName" \
		sh -c "$readyCommand" \
		2>&1 | tee "$tempFile" | grep -q "$readyCheck"
	do
		echo -n "   ${waitedSeconds}(${PIPESTATUS[0]},${PIPESTATUS[2]}):  "
		cat "$tempFile"

		# Check for service "${serviceName}" is not running
		if grep -q "service \"${serviceName}\" is not running" "$tempFile"; then
			seenErrors=$((seenErrors + 1))
		fi

		sleep 1
		waitedSeconds=$((waitedSeconds + 1))

		# Check for timeout
		if [ $waitedSeconds -ge $maximumWaitSeconds ]; then
			returnState=1
			echo
			echo "ERROR:  ${serviceName} did not become ready within ${maximumWaitSeconds} seconds!" >&2
			break
		fi

		# Check for too many errors
		if [ $seenErrors -ge $maximumErrors ]; then
			returnState=2
			echo
			echo "ERROR:  ${serviceName} has failed too many times!" >&2
			break
		fi
	done
	echo -n "   ${waitedSeconds}(${PIPESTATUS[0]},${PIPESTATUS[2]}):  "
	cat "$tempFile"
	echo

	rm -f "$tempFile"
	return $returnState
}
