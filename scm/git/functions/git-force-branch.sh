################################################################################
# Define a function to force the current Git branch to a specified branch name.
#
# Copyright 2025 William W. Kimball, Jr. MBA MSIS
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
fi

# Dynamically load the common logging functions
if [ -z "$LIB_DIRECTORY" ]; then
	# The common library directory is not set, so set it to the default value
	MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	PROJECT_DIRECTORY="$(cd "${MY_DIRECTORY}/../../../../" && pwd)"
	LIB_DIRECTORY="${PROJECT_DIRECTORY}/lib"
	readonly MY_DIRECTORY PROJECT_DIRECTORY LIB_DIRECTORY
fi
setLoggerSource="${LIB_DIRECTORY}/logging/set-logger.sh"
if ! source "$setLoggerSource"; then
	echo "ERROR:  Unable to source ${setLoggerSource}!" >&2
	exit 2
fi
unset setLoggerSource

###
# Force the current Git branch to the specified branch name.
#
# @param <string> $1 The branch name to switch to.
# @param <string> $2 The path to the Git repository directory.
#
# @return <integer> Returns 0 on success, or a non-zero error code on failure.
#
# @example
#   # Force the current Git branch to 'staging' in the specified repository
#   gitForceBranch "staging" "/path/to/repo"
##
function gitForceBranch() {
	local branchName=${1:?"ERROR:  Branch name must be provided as the first positional argument to ${FUNCNAME[0]}."}
	local repoDir=${2:?"ERROR:  Repository directory must be provided as the second positional argument to ${FUNCNAME[0]}."}

	logInfo "Forcing Git branch '${branchName}' in repository '${repoDir}'..."

	if ! pushd "$repoDir" >/dev/null; then
		logError "Failed to change directory to repository '$repoDir'."
		return 1
	fi

	# Log the current Git branch
	logInfo "All branches available to repository '${repoDir}':"
	git branch -a

	# Download all tags and branches for the repository from the root
	logInfo "Fetching all tags and branches for repository '${repoDir}'."
	if ! git checkout master && ! git checkout main; then
		logError "Failed to switch to the master or main branch in repository '$repoDir'."
		return 2
	fi
	if ! git fetch --all --tags --prune; then
		logError "Failed to fetch all tags and branches for repository '$repoDir'."
		return 3
	fi
	if ! git pull; then
		logError "Failed to pull latest changes for repository '$repoDir'."
		return 4
	fi

	# Force purge any and all local changes
	logInfo "Forcing purge of any and all local changes in repository '${repoDir}'."
	if ! git reset --hard HEAD && ! git clean -fd; then
		logError "Failed to reset and clean repository '$repoDir'."
		return 5
	fi

	# Attempt to switch to the specified branch
	logInfo "Attempting to switch repository '${repoDir}' to branch '${branchName}'..."
	if ! git checkout "$branchName"; then
		logError "Failed to switch repository '$repoDir' to branch '$branchName'."
		return 6
	fi

	# Report the current branch and its latest commit comment
	logInfo "Current branch in repository '${repoDir}': $(git rev-parse --abbrev-ref HEAD)"
	logInfo "Latest commit in branch '${branchName}': $(git log -1 --pretty=format:'%h %s')"

	# Return to the original directory
	if ! popd >/dev/null; then
		logError "Failed to return to the original directory after processing repository '$repoDir'."
		return 7
	fi
}
