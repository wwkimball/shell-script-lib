###############################################################################
# Define shell helper functions for use with Docker Compose.
#
# Copyright 2001, 2003, 2024, 2025 William W. Kimball, Jr., MBA, MSIS
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
###############################################################################

###
# Send commands to a remote host via SSH without displaying the output.
#
# From:  https://serverfault.com/a/764403
##
function silentSsh {
	local connectionString="$1"
	local commands="$2"
	if [ -z "$commands" ]; then
		commands=`cat`
	fi
	ssh -T -o StrictHostKeyChecking=no $connectionString "$commands"
}
