#!/usr/bin/env bash
###############################################################################
# Restart a set of remote TLS services.
#
# The first command-line argument must be an SSH connection-string in format:
# [user@]host, where user@ is optional.  All remaining command-line arguments
# specify which service(s) to restart using form:
# /path/to/deployment:service_name.
#
# Example:
# ./restart-remote-services.sh user@host.domain.tld \
#      /docker/deployment001:restart_me \
#      /docker/deployment002:restart_me_too
###############################################################################
myVersion='20240304-1'
myDirectory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly myVersion myDirectory

# Import the ssh helpers
if ! source "${myDirectory}/ssh-helpers.sh"; then
	echo "ERROR:  Failed to import SSH helpers!" >&2
	exit 2
fi

# The first positional command-line argument is the [user@]host
connectionString=${1:?"ERROR:  A connection string must be provided as the first positional arugment to $0!"}
shift

# All remaining positional command-line arguments are specifications of what to
# restart in the following form:
# /path/to/compose:service_name
silentSsh "${connectionString}" <<-EOCOMMANDS
	exitState=0
	for restartService in $@; do
		dirSpec=\${restartService%:*}
		serviceName=\${restartService#*:}
		pushd "\$dirSpec"
		echo "Restarting \${serviceName}..."
		if [ -x ./compose.sh ]; then
			./compose.sh restart "\${serviceName}"
		elif [ -f ./docker/docker-compose.yaml ]; then
			docker compose -f ./docker/docker-compose.yaml restart "\${serviceName}"
		elif [ -f ./docker/docker-compose.yml ]; then
			docker compose -f ./docker/docker-compose.yml restart "\${serviceName}"
		else
			docker compose restart "\${serviceName}"
		fi
		if [ 0 -ne \$? ] ; then
			echo "ERROR:  Failed to restart \${serviceName} at \${dirSpec}!" >&2
			exitState=1
		fi
		popd
	done
	exit \$exitState
EOCOMMANDS
