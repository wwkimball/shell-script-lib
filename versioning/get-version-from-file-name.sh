################################################################################
# Defines a function, getVersionFromFileName, which provides logic that can
# identify the version of a product from its file-name, provided the version
# number appears in the file-name in a reliable, identifiable way.
#
# Copyright 2001, 2018, 2025 William W. Kimball, Jr., MBA, MSIS
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

function getVersionFromFileName {
	local fileSpec fileName versionNumber
	fileSpec=${1:?"ERROR:  A file-name must be provided as the first positional argument to ${FUNCNAME[0]}."}
	fileName=${fileSpec##*/}

	# Strip off any RPM-style Release Tag
	if [[ $fileName =~ ^(.*[[:digit:]]+(\.[[:digit:]]+)*)-[[:digit:]].*$ ]]; then
		fileName=${BASH_REMATCH[1]}
	fi

	# Attempt to identify the version number
	versionNumber=
	if [[ $fileName =~ ^.+-([[:digit:]]+(\.[[:digit:]]+)*).*$ ]]; then
		versionNumber=${BASH_REMATCH[1]}
	elif [[ $fileName =~ ^.+[^[:digit:]\.]([[:digit:]]+(\.[[:digit:]]+)*).*$ ]]; then
		versionNumber=${BASH_REMATCH[1]}
	else
		errorOut 70 "A version number could not be found in file-name, ${fileName}."
	fi

	echo "$versionNumber"
}
