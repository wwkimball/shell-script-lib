###############################################################################
# Import the entire gammut of shell helpers.
###############################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# Constants
_myDir="${BASH_SOURCE[0]%/*}"
_myVersion="2025.05.09-1"
readonly _myDir _myVersion

# Logging facility
if ! source "${_myDir}/logging/set-logger.sh"; then
	echo "ERROR:  Unable to source ${_myDir}/logging/set-logger.sh" >&2
	exit 2
fi

# Docker compose helpers
if ! source "${_myDir}/docker/compose-helpers.sh"; then
	echo "ERROR:  Unable to source ${_myDir}/docker/compose-helpers.sh" >&2
	exit 2
fi

# Math helpers
if ! source "${_myDir}/math/math-helpers.sh"; then
	echo "ERROR:  Unable to source ${_myDir}/math/math-helpers.sh" >&2
	exit 2
fi

# SSH helpers
if ! source "${_myDir}/ssh/ssh-helpers.sh"; then
	echo "ERROR:  Unable to source ${_myDir}/ssh/ssh-helpers.sh" >&2
	exit 2
fi

# Versioning helpers
if ! source "${_myDir}/versioning/release-helpers.sh"; then
	echo "ERROR:  Unable to source ${_myDir}/versioning/release-helpers.sh" >&2
	exit 2
fi
