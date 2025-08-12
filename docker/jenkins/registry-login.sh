#!/usr/bin/env bash
################################################################################
# Log Jenkins into the Docker registry.
#
# One set of the following environment variables must be set.  Which you choose
# to use is up to you.
# - SET 1:  Fully Dynamic Build
#   - DEPLOYMENT_STAGE
#   - DOCKER_REGISTRY_SOCKET_${DEPLOYMENT_STAGE}
#   - DOCKER_REGISTRY_USERNAME_${DEPLOYMENT_STAGE}
#   - DOCKER_REGISTRY_PASSWORD_${DEPLOYMENT_STAGE}
# - SET 2:  Static Build
#   - DOCKER_REGISTRY_SOCKET
#   - DOCKER_REGISTRY_USERNAME
#   - DOCKER_REGISTRY_PASSWORD
################################################################################
# Derived constants
LIB_DIR="${WORKSPACE}/lib"
DOCKER_DIR="${WORKSPACE}/docker"
DEPLOY_D_DIR="${WORKSPACE}/deploy.d"
readonly LIB_DIR DOCKER_DIR DEPLOY_D_DIR

# Import the standard library's logging functions
if ! source "${LIB_DIR}/logging/set-logger.sh"; then
	echo "ERROR:  Unable to import the logging library." >&2
	exit 2
fi

if [ -z "$DOCKER_REGISTRY_SOCKET" ] \
	|| [ -z "$DOCKER_REGISTRY_USERNAME" ] \
	|| [ -z "$DOCKER_REGISTRY_PASSWORD" ]
then
	if [ -z "$DEPLOYMENT_STAGE" ]; then
		errorOut 1 "ERROR:  DEPLOYMENT_STAGE must be set if any registry variables are not set."
	fi

	# For each missing value, find the name of its registry variable for the
	# current deployment stage and infer its value.
	if [ -z "$DOCKER_REGISTRY_SOCKET" ]; then
		DOCKER_REGISTRY_SOCKET_VAR="DOCKER_REGISTRY_SOCKET_${DEPLOYMENT_STAGE}"
		DOCKER_REGISTRY_SOCKET="${!DOCKER_REGISTRY_SOCKET_VAR}"
	fi
	if [ -z "$DOCKER_REGISTRY_USERNAME" ]; then
		DOCKER_REGISTRY_USERNAME_VAR="DOCKER_REGISTRY_USERNAME_${DEPLOYMENT_STAGE}"
		DOCKER_REGISTRY_USERNAME="${!DOCKER_REGISTRY_USERNAME_VAR}"
	fi
	if [ -z "$DOCKER_REGISTRY_PASSWORD" ]; then
		DOCKER_REGISTRY_PASSWORD_VAR="DOCKER_REGISTRY_PASSWORD_${DEPLOYMENT_STAGE}"
		DOCKER_REGISTRY_PASSWORD="${!DOCKER_REGISTRY_PASSWORD_VAR}"
	fi
fi

# Validate registry variables
if [ -z "$DOCKER_REGISTRY_SOCKET" ]; then
	errorOut 1 "DOCKER_REGISTRY_SOCKET or DEPLOYMENT_STAGE and DOCKER_REGISTRY_SOCKET_\${DEPLOYMENT_STAGE} must be set."
fi
if [ -z "$DOCKER_REGISTRY_USERNAME" ]; then
	errorOut 1 "DOCKER_REGISTRY_USERNAME or DEPLOYMENT_STAGE and DOCKER_REGISTRY_USERNAME_\${DEPLOYMENT_STAGE} must be set."
fi
if [ -z "$DOCKER_REGISTRY_PASSWORD" ]; then
	errorOut 1 "DOCKER_REGISTRY_PASSWORD or DEPLOYMENT_STAGE and DOCKER_REGISTRY_PASSWORD_\${DEPLOYMENT_STAGE} must be set."
fi

# Log in to the Docker registry but suppress warnings about exposed credentials
echo "$DOCKER_REGISTRY_PASSWORD" | docker login \
	--username "$DOCKER_REGISTRY_USERNAME" \
	--password-stdin "$DOCKER_REGISTRY_SOCKET" \
	>/dev/null
if [ $? -ne 0 ]; then
	errorOut 3 "Failed to log in to the Docker Registry."
fi
