###############################################################################
# Define shell helper functions for use with Docker Compose.
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
###############################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# This is an import helper; just import the various function definitions
# from the other files in the versioning directory.
_thisDir="${BASH_SOURCE[0]%/*}"
source "${_thisDir}/decrement-dotted-version.sh"
source "${_thisDir}/get-release-number-for-version.sh"
source "${_thisDir}/get-version-from-file-name.sh"
