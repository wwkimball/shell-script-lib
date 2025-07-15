################################################################################
# Load all SCM-related helpers.
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
