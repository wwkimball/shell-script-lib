#!/bin/bash
################################################################################
# Build the Docker image(s) for this project.
#
# External control variables:
# TMPDIR <string> The directory in which to create temporary files like baked
#                 Docker Compose files.  The default is the system's temporary
#                 directory.
# DOCKER_SCOUT_ENABLED <boolean> Whether to enable Docker Scout for the built
#                                images.  Default is false because Scout is
#                                not available in all Docker installations.
#
# Optional external assets:
# - build-pre.sh <DEPLOYMENT_STAGE> <BAKED_DOCKER_COMPOSE_FILE>
#   A script to run just before building the Docker image(s).  Such a script is
#   run in the same context as this script, so it can manipulate the baked
#   Docker Compose file before it is used but will have only a local copy
#   of the environment.  The script file must be in the project directory -- two
#   directory levels higher than the directory containing this parent script --
#   and be executable by the user running this script.  It will receive
#   the deployment stage name and the name of the baked Docker Compose file as
#   command-line arguments, in that order.  Using this script is optional and
#   is most useful for preparing the build directory structure.  DO NOT USE THIS
#   SCRIPT TO PERFORM ANY DOCKER OPERATIONS -- the images and containers will
#   not yet exist -- AND DO NOT ATTEMPT TO SET ANY ENVIRONMENT VARIABLES YOU
#   INTEND FOR THIS SCRIPT TO USE (because all such environment variable changes
#   will be discarded once your script ends).
# - build-post.sh <DEPLOYMENT_STAGE> <BAKED_DOCKER_COMPOSE_FILE>
#   A script to run after building the Docker image(s).  Such a script is run in
#   the same context as this script, so it will have a a local copy of the
#   environment, though any changes to the baked Docker Compose file will be
#   moot.  The script file must be in the project directory -- two directory
#   levels higher than the directory containing this parent script -- and be
#   executable by the user running this script.
# - build-post-<service>.sh
#   This is a script to run within the named service container after building
#   its Docker image.  It will receive no command-line arguments.  Running this
#   script will have NO EFFECT on the built image but rather only upon a local
#   instance of its container.  Further, this script will NOT have access to the
#   context of this parent script.  The container will be started to facilitate
#   script execution.  Set or omit --start to indicate whether you wish for the
#   container to remain running upon completion.  The script file must be in the
#   project directory -- two directory levels higher than the directory
#   containing this parent script -- but it does not need to be executable.
#
# Copyright 2025 William W. Kimball, Jr. MBA MSIS
# All rights reserved.
################################################################################
# Constants
MY_VERSION='2025.04.16-1'
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIRECTORY="$(cd "${MY_DIRECTORY}/../../" && pwd)"
LIB_DIRECTORY="${PROJECT_DIRECTORY}/lib"
DOCKER_DIRECTORY="${PROJECT_DIRECTORY}/docker"
COMPOSE_BASE_FILE="${DOCKER_DIRECTORY}/docker-compose.yaml"
DEPLOY_STAGE_DEVELOPMENT=development
DEPLOY_STAGE_LAB=lab
DEPLOY_STAGE_QA=qa
DEPLOY_STAGE_STAGING=staging
DEPLOY_STAGE_PRODUCTION=production
readonly MY_VERSION MY_DIRECTORY PROJECT_DIRECTORY LIB_DIRECTORY \
	DOCKER_DIRECTORY COMPOSE_BASE_FILE DEPLOY_STAGE_DEVELOPMENT \
	DEPLOY_STAGE_LAB DEPLOY_STAGE_QA DEPLOY_STAGE_STAGING \
	DEPLOY_STAGE_PRODUCTION

# Import the shell helpers
if ! source "${LIB_DIRECTORY}/shell-helpers.sh"; then
	echo "ERROR:  Failed to import shell helpers!" >&2
	exit 2
fi

# Check for Docker Scout enablement; any truthy value will do
_withDockerScout=false
if [ -n "${DOCKER_SCOUT_ENABLED}" ]; then
	if [[ "${DOCKER_SCOUT_ENABLED}" =~ ^[Tt][Rr][Uu][Ee]$ ]] || \
		[[ "${DOCKER_SCOUT_ENABLED}" =~ ^[Yy][Ee][Ss]$ ]] || \
		[[ "${DOCKER_SCOUT_ENABLED}" =~ ^[Oo][Nn]$ ]] || \
		[[ "${DOCKER_SCOUT_ENABLED}" =~ ^[1]$ ]]
	then
		_withDockerScout=true
	fi
fi

# Process command-line arguments, if there are any
_bakedDir="${TMPDIR:-$(dirname $(mktemp -u))}"
_cleanResources=false
_deployStage=$DEPLOY_STAGE_DEVELOPMENT
_hasErrors=false
_imagesDirectory="${DOCKER_DIRECTORY}/images"
_imageVersionFile="${PROJECT_DIRECTORY}/VERSION"
_makePortable=true
_progressMode=auto
_pushImages=true
_saveBakedFile=false
_servicesRunning=false
_startEnvironment=false
while [ $# -gt 0 ]; do
	case $1 in
		-b|--baked)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_bakedDir="$2"
				_saveBakedFile=true
				shift
			fi
			;;

		-c|--clean)
			_cleanResources=true
			;;

		-d|--stage)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				if [[ "$2" =~ ^[Dd] ]]; then
					_deployStage=$DEPLOY_STAGE_DEVELOPMENT
					_pushImages=false
				elif [[ "$2" =~ ^[Ll] ]]; then
					_deployStage=$DEPLOY_STAGE_LAB
				elif [[ "$2" =~ ^[Qq] ]]; then
					_deployStage=$DEPLOY_STAGE_QA
				elif [[ "$2" =~ ^[Ss] ]]; then
					_deployStage=$DEPLOY_STAGE_STAGING
				elif [[ "$2" =~ ^[Pp] ]]; then
					_deployStage=$DEPLOY_STAGE_PRODUCTION
				else
					logError "Unsupported value, ${2}, for $1 option."
					_hasErrors=true
				fi
				shift
			fi
			;;

		-h|--help)
			cat <<EOHELP
$0 [OPTIONS] [--] [BUILD_SERVICE...]

Builds the Docker image(s) for this project.  OPTIONS include:
  -b BAKED_DIR, --baked BAKED_DIR
       The directory in which to permanently save the baked Docker Compose file,
       taking the name of any selected override file.  Left unset, the system
       default temporary directory is used and the baked file is automatically
       destroyed when the script exits.
  -c, --clean
       Clean the Docker resources before building.  The default is to NOT
       clean the resources.
  -d DEPLOY_STAGE, --stage DEPLOY_STAGE
       Indicate which deployment stage to run against.  This controls which
       Docker Compose override file is used based on the presence of the
       DEPLOY_STAGE string within the file name matching the pattern:
       docker-compose.DEPLOY_STAGE.yaml.  Must be one of:
         * ${DEPLOY_STAGE_DEVELOPMENT}
         * ${DEPLOY_STAGE_LAB}
         * ${DEPLOY_STAGE_QA}
         * ${DEPLOY_STAGE_STAGING}
         * ${DEPLOY_STAGE_PRODUCTION}
       The default is ${_deployStage}.  For the ${DEPLOY_STAGE_DEVELOPMENT}
       mode, this setting also implies that the --no-portable and --no-push
       options are set.
  -h, --help
       Display this help message and exit.
  -I, --no-portable
       Do NOT save portable copies of the new image(s).  The default is to
       save portable copies of the new image(s).  Implied when DEPLOY_STAGE is
       ${DEPLOY_STAGE_DEVELOPMENT}.
  -i IMAGE_DIR, --images IMAGE_DIR
       The directory to save portable copies of the new image to.  Defaults to
       ${_imagesDirectory}.
  -P, --no-push
       Do NOT push the new image(s) to the Docker registry.  The default is
       to push the new image(s) to the registry.  Implied when DEPLOY_STAGE is
       ${DEPLOY_STAGE_DEVELOPMENT}.
  -p PROGRESS_MODE, --progress PROGRESS_MODE
       The Docker Compose progress mode to use while building the docker
       image(s).  The default is ${_progressMode}.  Refer to the Docker Compose
       documentation for the available options.
  -r VERSION_FILE, --version-file VERSION_FILE
       The file containing the base version number.  A version file is required
       in order to properly version and build-tag Docker images via this script.
       The default is:
       ${_imageVersionFile}.
  -S, --with-scout
       Enable Docker Scout security scanning for images built by this script.
       Because most Docker installations do not include Scout, this option is
       off by default.  You can externally control this option by setting the
       DOCKER_SCOUT_ENABLED environment variable to any "truthy" value.
  -s, --start
       Start the Docker environment after building.  The default is to NOT
       start the environment.  Note that some operations will start the
       environment automatically in order to perform their tasks.  In that
       case, setting this option will simply keep the environment running
       after the operation completes.  Implies --no-portable and --no-push.
  -v, --version
       Display the version of this script and exit.

BUILD_SERVICE   One or more space-delimited names of services to build.
                Defaults to all services defined in the Docker Compose file
                which have 'build' attributes.

EOHELP
			exit 0
			;;

		-I|--no-portable)
			_makePortable=false
			;;

		-i|--images)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_imagesDirectory="$2"
				shift
			fi
			;;

		-p|--progress)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_progressMode="$2"
				shift
			fi
			;;

		-P|--no-push)
			_pushImages=false
			;;

		-r|--version-file)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!" >&2
				_hasErrors=true
			else
				_imageVersionFile="$2"
				shift
			fi
			;;

		-S|--with-scout)
			_withDockerScout=true
			;;

		-s|--start)
			_startEnvironment=true
			makePortable=false
			pushImages=false
			;;

		-v|--version)
			echo "$0 ${MY_VERSION}"
			exit 0
			;;

		--)	# Explicit end of options
			shift
			break
			;;

		-*)
			logError "Unknown option:  $1"
			_hasErrors=true
			;;

		*)	# Implicit end of options
			break
			;;
	esac

	shift
done

# Any remaining arguments are assumed to be the names of services to build
if [ 0 -lt $# ]; then
	buildServices=("$@")
	logInfo "Building only the following service(s):  ${buildServices[*]}"
fi

# Verify Docker is running
if ! docker info >/dev/null 2>&1; then
	logError "Docker is not running!" >&2
	_hasErrors=true
fi

# Verify Docker Compose is installed
if ! docker compose --version >/dev/null 2>&1; then
	logError "Docker Compose is not installed!" >&2
	_hasErrors=true
fi

# yamlpath (and Python 3) is required to parse various files
if ! yaml-get --version >/dev/null 2>&1; then
	logError "yamlpath (https://github.com/wwkimball/yamlpath?tab=readme-ov-file#installing) is not installed!" >&2
	_hasErrors=true
fi

# Get the base version number of the application
if [ ! -f "$_imageVersionFile" ]; then
	logError "Missing ${_imageVersionFile} file!" >&2
	_hasErrors=true
else
	baseVersion=$(head -1 "$_imageVersionFile")
	if [ -z "$baseVersion" ]; then
		logError "Version number not present in the first line of, ${_imageVersionFile}!" >&2
		_hasErrors=true
	fi
fi

# Bail if any system state or user input errors have been detected
if $_hasErrors; then
	exit 1
fi

# Identify the Docker Compose override files to use
overrideComposeFile="${DOCKER_DIRECTORY}/docker-compose.${_deployStage}.yaml"
if [ ! -f "$overrideComposeFile" ]; then
	overrideComposeFile=
fi

# Work from a pre-baked, possibly temporary Docker Compose file
bakedComposeFile=
if $_saveBakedFile; then
	bakedComposeFile="${_bakedDir}/docker-compose.${_deployStage}.baked.yaml"
	if [ ! -d "$_bakedDir" ]; then
		if ! mkdir -p "$_bakedDir"; then
			errorOut 2 "Unable to create ${_bakedDir}!"
		fi
	fi
	if [ -e "$bakedComposeFile" ]; then
		if ! rm -f "$bakedComposeFile"; then
			errorOut 3 "Unable to remove ${bakedComposeFile}!"
		fi
	fi
else
	bakedComposeFile=$(mktemp)
	trap "rm -f '$bakedComposeFile'" EXIT
fi
dynamicBakeComposeFile "$bakedComposeFile" "$_deployStage" "$DOCKER_DIRECTORY"
if [ 0 -ne $? ]; then
	noBakeErrorMessage="Unable to bake ${COMPOSE_BASE_FILE}"
	if [ -n "$overrideComposeFile" ]; then
		noBakeErrorMessage+=" with ${overrideComposeFile}"
	fi
	noBakeErrorMessage+="!"
	errorOut 3 "$noBakeErrorMessage"
fi

# When no services are specified, build all services having a build context
if [ 1 -gt ${#buildServices[@]} ]; then
	buildServices=($(yaml-get --nostdin --query='services.*.build[parent()][name()]' "$bakedComposeFile"))

	# There must be at least one service to build
	if [ 1 -gt ${#buildServices[@]} ]; then
		errorOut 1 "Could not determine the services to build!"
	else
		buildMessage="Building all service(s) defined in ${COMPOSE_BASE_FILE}"
		if [ -n "$overrideComposeFile" ]; then
			buildMessage+=" and ${overrideComposeFile}"
		fi
		buildMessage+=":  ${buildServices[*]}"
		logInfo "$buildMessage"
		unset buildMessage
	fi
fi

# Force certain options when running in development mode; these may not have
# been set explicitly by the user, but they are required for development.
if [ "$_deployStage" == "$DEPLOY_STAGE_DEVELOPMENT" ]; then
	_makePortable=false
	_pushImages=false
fi

logInfo "Building version ${baseVersion} of the ${_deployStage} environment..."
infoText="  Using ${COMPOSE_BASE_FILE}"
if [ -f "$overrideComposeFile" ]; then
	infoText+=" and ${overrideComposeFile}"
fi
infoText+="."
logLine "$infoText"
echo

# On request, clean the Docker environment
if $_cleanResources; then
	logLine "Cleaning the Docker environment..."
	dockerCompose "$bakedComposeFile" "" \
		--profile "$_deployStage" \
		down --remove-orphans --rmi all --volumes
	if [ 0 -ne $? ]; then
		errorOut 4 "Failed to clean the Docker environment."
	fi
else
	# Stop any running containers
	logLine "\nStopping any running containers..."
	dockerCompose "$bakedComposeFile" "" \
		--profile "$_deployStage" \
		stop
	if [ 0 -ne $? ]; then
		errorOut 5 "Failed to stop any running containers."
	fi
fi

# Always pull the latest ancilliary images
dockerCompose "$bakedComposeFile" "" \
	--profile "$_deployStage" \
	pull --ignore-buildable
if [ 0 -ne $? ]; then
	errorOut 6 "Failed to pull the latest Docker images."
fi

# When exporting portable images, ensure the target directory exists
if $_makePortable; then
	if [ ! -d "$_imagesDirectory" ]; then
		mkdir "$_imagesDirectory"
	fi

	imageIDFile="${_imagesDirectory}/LAST-SAVED-IMAGE-IDS.txt"
	if [ -f "$imageIDFile" ]; then
		rm -f "$imageIDFile"
	fi
fi

# Build each new Docker image; switch to the project directory first to help
# resolve relative paths.  Note that the build context MUST BE the project
# directory lest Docker COPY commands fail to find files.  This is becuase
# Docker explicitly prohibits copying files from outside the build context and
# this project's main files are indeed outside the Docker build context, and
# reasonably so.
cd "${PROJECT_DIRECTORY}"

# Run build-pre.sh when present and executable
buildPreScript="${PROJECT_DIRECTORY}/build-pre.sh"
logLine "Checking for pre-build script, ${buildPreScript}..."
if [ -f "$buildPreScript" ]; then
	if ! "$buildPreScript" "$_deployStage" "$bakedComposeFile"; then
		errorOut 7 "Failed to run pre-build script, ${buildPreScript}!  Is it executable?"
	fi
fi

for buildService in "${buildServices[@]}"; do
	# Identify the image name and version
	imageNameYAMLPath="services.${buildService}.image"
	imageComposeName=$(yaml-get --nostdin --query="$imageNameYAMLPath" "$bakedComposeFile")
	if [ 0 -ne $? ]; then
		missingImageNameMessage="Failed to get image name from ${COMPOSE_BASE_FILE}"
		if [ -n "$overrideComposeFile" ]; then
			missingImageNameMessage+=" and ${overrideComposeFile}"
		fi
		missingImageNameMessage+="!"
		errorOut 8 "$missingImageNameMessage"
	fi
	longDockerImageName=${imageComposeName%:*}				# Strip version
	dockerImageVersionedName=${imageComposeName#*/}			# Strip registry, keep user
	shortDockerImageName="${dockerImageVersionedName%%:*}"	# Strip version
	dockerImageBaseName=${shortDockerImageName##*/}			# Strip registry and user
	dockerFileBaseName=${shortDockerImageName//\//-}		# Replace slashes with dashes

	# Identify the next available build number for each service's artifact
	buildNumber=$(getReleaseNumberForVersion "$dockerImageBaseName" "$baseVersion")
	if [ 0 -ne $? ]; then
		errorOut 9 "Could not determine the build number for ${dockerImageBaseName}!"
	fi
	dockerImageVersion="${baseVersion}-${buildNumber}"

	# Infer various reference and file names
	dockerImageRef="${longDockerImageName}:${dockerImageVersion}"
	portableFileName="${dockerFileBaseName}-${dockerImageVersion}.tar.bz"
	portableQualifiedFile="${_imagesDirectory}/${portableFileName}"

	# Reset the version number for this service in the Docker Compose file
	logLine "Setting image to ${dockerImageRef} at ${imageNameYAMLPath} in ${bakedComposeFile}..."
	yaml-set --nostdin --change="$imageNameYAMLPath" --value="$dockerImageRef" "$bakedComposeFile"
	if [ 0 -ne $? ]; then
		errorOut 10 "Unable to update image in ${bakedComposeFile} to ${dockerImageRef}!"
	fi

	# Perform the actual build
	logCharLine "-"
	logInfo "Building version ${dockerImageVersion} of ${dockerImageBaseName} for ${buildService}..."
	if ! dockerCompose "$bakedComposeFile" "" \
		--profile "$_deployStage" \
		--progress "$_progressMode" \
		build --pull ${buildService}
	then
		errorOut 11 "Docker build failed!"
	fi

	# Run build-post-<service>.sh within the container when present
	buildPostServiceScript="${PROJECT_DIRECTORY}/build-post-${buildService}.sh"
	if [ -f "$buildPostServiceScript" ]; then
		logInfo "Running post-build script, ${buildPostServiceScript}, in the ${buildService} container..."

		# Extract service configuration from the baked compose file
		serviceImagePath="services.${buildService}.image"
		serviceImage=$(yaml-get --nostdin --query="$serviceImagePath" "$bakedComposeFile")
		if [ 0 -ne $? ]; then
			errorOut 12 "Failed to get image name for service ${buildService} from ${bakedComposeFile}!"
		fi

		# Build docker run arguments from compose configuration
		declare -a dockerRunArgs=()
		dockerRunArgs+=(--rm)  # Remove container when it exits
		dockerRunArgs+=(--interactive)  # Keep STDIN open for script input

		# Extract and add environment variables
		envVarsPath="services.${buildService}.environment"
		if yaml-get --nostdin --query="$envVarsPath" "$bakedComposeFile" >/dev/null 2>&1; then
			while IFS= read -r envVar; do
				if [[ "$envVar" =~ ^[^=]+= ]]; then
					# Environment variable with value
					dockerRunArgs+=(--env "$envVar")
				else
					# Environment variable name only (inherit from host)
					dockerRunArgs+=(--env "$envVar")
				fi
			done < <(yaml-get --nostdin --query="$envVarsPath.*" "$bakedComposeFile" 2>/dev/null | grep -v "^$")
		fi

		# Extract and add env_file entries
		envFilePath="services.${buildService}.env_file"
		if yaml-get --nostdin --query="$envFilePath" "$bakedComposeFile" >/dev/null 2>&1; then
			while IFS= read -r envFile; do
				if [ -n "$envFile" ] && [ -f "${DOCKER_DIRECTORY}/${envFile}" ]; then
					dockerRunArgs+=(--env-file "${DOCKER_DIRECTORY}/${envFile}")
				fi
			done < <(yaml-get --nostdin --query="$envFilePath.*" "$bakedComposeFile" 2>/dev/null)
		fi

		# Extract and mount secrets
		secretsPath="services.${buildService}.secrets"
		if yaml-get --nostdin --query="$secretsPath" "$bakedComposeFile" >/dev/null 2>&1; then
			while IFS= read -r secretName; do
				if [ -n "$secretName" ]; then
					# Get secret file path from the secrets section
					secretFilePath=$(yaml-get --nostdin --query="secrets.${secretName}.file" "$bakedComposeFile" 2>/dev/null)
					if [ -n "$secretFilePath" ] && [ -f "${DOCKER_DIRECTORY}/${secretFilePath}" ]; then
						dockerRunArgs+=(--mount "type=bind,source=${DOCKER_DIRECTORY}/${secretFilePath},target=/run/secrets/${secretName},readonly")
					fi
				fi
			done < <(yaml-get --nostdin --query="$secretsPath.*" "$bakedComposeFile" 2>/dev/null)
		fi

		# Run the test script in a disposable container
		if cat "$buildPostServiceScript" | docker run "${dockerRunArgs[@]}" "$serviceImage" /bin/sh -s; then
			logInfo "Post-build script completed successfully."
		else
			errorOut 13 "Failed to run the post-build script, ${buildPostServiceScript}, in the ${buildService} container!"
		fi
	fi

	# Show a brief security summary of the new image
	if $_withDockerScout; then
		logLine "Running Docker Scout quickview on the new image, ${dockerImageRef}..."
		docker scout quickview "local://${dockerImageRef}"
	fi

	# Tag this new image as latest
	logLine "Tagging the new image as latest..."
	docker image tag "${dockerImageRef}" "${longDockerImageName}:latest"
	if [ 0 -ne $? ]; then
		errorOut 14 "Could not tag the new image as latest!"
	fi

	# Delete all old versions of the new image
	logLine "Deleting old image versions of ${longDockerImageName}..."

	# Get the current image ID to avoid deleting it
	currentImageID=$(docker images --format="{{.ID}}" "${dockerImageRef}")

	declare -a purgeIDs=($(\
		docker images \
			--format="{{.ID}} {{.Tag}}" \
			"${longDockerImageName}:*" \
		| grep -v ":latest$" \
		| grep -v ":${dockerImageVersion}$" \
		| awk '{print $1}' \
		| sort -u \
		| grep -v "^${currentImageID}$"
	))
	if [ 0 -lt ${#purgeIDs[@]} ]; then
		logLine "Deleting old image versions of ${longDockerImageName}:  ${purgeIDs[*]}"
		echo "${purgeIDs[*]}" | xargs docker rmi --force
	fi

	# Optionally push to the Docker registry
	if $_pushImages; then
		# Note that two pushes are required because Docker Compose will only
		# push the tag that is present in the Compose file, which is the
		# versioned tag.  We want to push both the versioned and latest tags.
		logInfo "Pushing the new versioned image to the registry..."
		dockerCompose "$bakedComposeFile" "" \
			--profile "$_deployStage" \
			push ${buildService}
		if [ 0 -ne $? ]; then
			errorOut 15 "Could not push the new versioned image to the registry!"
		fi

		logLine "Pushing tag, latest, to the registry for the new image..."
		docker push "${longDockerImageName}:latest"
		if [ 0 -ne $? ]; then
			errorOut 16 "Could not push the 'latest' image to the registry!"
		fi
	else
		logLine "Skipping push of the new image to the registry."
	fi

	# --------------------------------------------------------------------------
	# Everything beyond this point is for exporting a portable image
	# --------------------------------------------------------------------------
	if ! $_makePortable; then
		logInfo "Skipping portable copy of the new image."
		continue
	fi

	# Track the ID of the new image for deployment
	savedImageID=$(docker images --format="{{.ID}}" ${dockerImageRef})
	if [ 0 -ne $? ]; then
		errorOut 17 "Could not determine the ID of the new image!"
	fi
	echo -e "${dockerImageBaseName}:${dockerImageVersion}\t${savedImageID}\t${portableQualifiedFile}" >>"$imageIDFile"

	# Save a portable copy of each new image
	logLine "Deleting any old portable copies of ${dockerFileBaseName}..."
	rm "$_imagesDirectory"/${dockerFileBaseName}-*.tar.bz

	logInfo "Saving a portable copy of the newest image, ${dockerImageRef}, as ${portableQualifiedFile}..."
	docker image save "$dockerImageRef" | bzip2 >"$portableQualifiedFile"
	retValCompress=${PIPESTATUS[1]}
	retValSave=${PIPESTATUS[0]}
	if [ 0 -ne $retValSave ]; then
		errorOut 18 "Could not save the new image; got exit code, ${retValSave}!"
	elif [ 0 -ne $retValCompress ]; then
		errorOut 19 "Could not compress the new image; got exit code, ${retValCompress}!"
	fi

	cat <<EOF

You can import the new image using this command (it will be version-tagged):
	docker load -i ${portableFileName}

When you want the newly imported image to additionally be tagged 'latest', also
run:
	docker image tag ${savedImageID} ${shortDockerImageName}:latest

EOF
done

# Run build-post.sh when present and executable
buildPostScript="${PROJECT_DIRECTORY}/build-post.sh"
logLine "Checking for post-build script, ${buildPostScript}..."
if [ -f "$buildPostScript" ]; then
	if ! "$buildPostScript" "$_deployStage" "$bakedComposeFile"; then
		errorOut 31 "Failed to run post-build script!  Is it executable?"
	fi
fi

if $_servicesRunning; then
	if ! $_startEnvironment; then
		# Stop the environment
		./stop.sh --stage "$_deployStage"
		if [ 0 -ne $? ]; then
			errorOut 20 "Failed to stop the environment!"
		fi
		_servicesRunning=false
	fi
else
	if $_startEnvironment; then
		# Bring up the environment and wait for the primary service to be ready
		./start.sh --stage "$_deployStage"
		if [ 0 -ne $? ]; then
			errorOut 21 "Failed to start the environment!"
		fi
		_servicesRunning=true
	fi
fi

cat <<-EOF

Your ${_deployStage} environment is built and ready!  The local container(s) are
EOF
if $_servicesRunning; then
	cat <<-EOF
up and running!  To stop the environment, run:
	./stop.sh --stage ${_deployStage}
EOF
else
	cat <<-EOF
stopped.  To start the environment, run:
	./start.sh --stage ${_deployStage}
EOF
fi
