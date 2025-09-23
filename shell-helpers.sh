###############################################################################
# Import the entire gammut of shell helpers.
###############################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# Constants
STD_SHELL_LIB_VERSION="2025.09.17-1"
readonly STD_SHELL_LIB_VERSION

# Reduce directory resolution overhead for all further library calls by caching
# the base directory of the library as STD_SHELL_LIB, when it isn't already set.
if [ -z "$STD_SHELL_LIB" ]; then
	STD_SHELL_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
export STD_SHELL_LIB

# Logging facility
if ! source "${STD_SHELL_LIB}/logging/set-logger.sh"; then
	echo "ERROR:  Unable to source ${STD_SHELL_LIB}/logging/set-logger.sh" >&2
	exit 2
fi

# General Docker helpers
if ! source "${STD_SHELL_LIB}/docker/source-functions.sh"; then
	echo "ERROR:  Unable to source ${STD_SHELL_LIB}/docker/source-functions.sh" >&2
	exit 2
fi

# Math helpers
if ! source "${STD_SHELL_LIB}/math/math-helpers.sh"; then
	echo "ERROR:  Unable to source ${STD_SHELL_LIB}/math/math-helpers.sh" >&2
	exit 2
fi

# SSH helpers
if ! source "${STD_SHELL_LIB}/ssh/ssh-helpers.sh"; then
	echo "ERROR:  Unable to source ${STD_SHELL_LIB}/ssh/ssh-helpers.sh" >&2
	exit 2
fi

# Versioning helpers
if ! source "${STD_SHELL_LIB}/versioning/release-helpers.sh"; then
	echo "ERROR:  Unable to source ${STD_SHELL_LIB}/versioning/release-helpers.sh" >&2
	exit 2
fi

# SCM helpers
if ! source "${STD_SHELL_LIB}/scm/scm-helpers.sh"; then
	echo "ERROR:  Unable to source ${STD_SHELL_LIB}/scm/scm-helpers.sh" >&2
	exit 2
fi
