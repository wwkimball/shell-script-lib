###############################################################################
# Define shell helper functions for use with Docker Compose.
###############################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# This is an import helper; just import the various function definitions
# from the other files.
source "${BASH_SOURCE[0]%/*}/get-release-number-for-version.sh"
source "${BASH_SOURCE[0]%/*}/get-version-from-file-name.sh"
