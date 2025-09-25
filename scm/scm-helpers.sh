################################################################################
# Load all SCM-related helpers.
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

# For each subdirectory of the directory containing this file, source all files
# matching the pattern, "${subdir}/${subDir}-helpers.sh".
_scmParentDir="${BASH_SOURCE[0]%/*}"
for _scmSpecDir in "${_scmParentDir}"/*; do
	if [ -d "$_scmSpecDir" ]; then
		_scmSpecDirName="${_scmSpecDir##*/}"
		_scmSpecDirFile="${_scmSpecDir}/${_scmSpecDirName}-helpers.sh"
		if [ -f "$_scmSpecDirFile" ]; then
			if ! source "$_scmSpecDirFile"; then
				echo "ERROR:  Unable to source ${_scmSpecDirFile}!" >&2
				exit 127
			fi
		fi
	fi
done
unset _scmParentDir _scmSpecDir _scmSpecDirName _scmSpecDirFile
