#!/usr/bin/env bash
###############################################################################
# Deploy this project to a remote server.
#
# A pre-baked Docker Compose configuration file is copied to the remote host
# (obviating the various .env* files).  Portable image files are copied to the
# remote host and registered with Docker unless the --no-portable option is
# specified.
#
# Copyright 2025 William W. Kimball, Jr. MBA MSIS
# All rights reserved.
###############################################################################
# Constants
MY_VERSION='2025.04.18-1'
MY_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIRECTORY="$(cd "${MY_DIRECTORY}/../../" && pwd)"
LIB_DIRECTORY="${MY_DIRECTORY}/lib"
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
	logError "Failed to import shell helpers!" >&2
	exit 2
fi

# Process command-line arguments
_deployPortable=true
_deployStage=$DEPLOY_STAGE_DEVELOPMENT
_deployToHosts=()
_destinationDir=/docker/$(basename "${PROJECT_DIRECTORY}")
_dockerGroup=docker
_hasErrors=false
_imagesDirectory="${DOCKER_DIRECTORY}/images"
_startStack=false
while [ $# -gt 0 ]; do
	case $1 in
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

		-g|--group)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_dockerGroup="$2"
			fi
			shift
			;;

		-h|--help)
			cat <<EOF
Usage: $0 [OPTIONS] [--] HOST...

Options:
  -d DEPLOY_STAGE, --stage DEPLOY_STAGE
       Indicate which run mode to use.  Must be one of:
         * ${DEPLOY_STAGE_DEVELOPMENT}
         * ${DEPLOY_STAGE_LAB}
         * ${DEPLOY_STAGE_QA}
         * ${DEPLOY_STAGE_STAGING}
         * ${DEPLOY_STAGE_PRODUCTION}
       The default is ${_deployStage}.  This controls which Docker Compose
       override file is used based on the presence of the DEPLOY_STAGE string
       within the file name matching the pattern:  docker-compose.*.yaml.
  -g DOCKER_GROUP, --group DOCKER_GROUP
       Remote, non-root group whose members are allowed to execute Docker
       commands (default:  ${_dockerGroup})
  -h, --help
       Display this help message and exit
  -P, --no-portable
       Do NOT deploy portable copies of the image(s).  The default is to
       deploy portable copies of the new image(s) when they exist at
       PORTABLE_DIR.
  -i IMAGE_DIR, --images IMAGE_DIR
       The directory where locally-built images are stored.  Defaults to:
       ${_imagesDirectory}
  -r REMOTE_DIR, --dir REMOTE_DIR
       Destination directory on the remote host.  Defaults to:
       ${_destinationDir}
  -s, --start
       Start the service stack after deployment.
  -v, --version
       Display the version number and exit

Arguments:
     HOST  Space-delimited list of hosts to deploy to.  At least one host must
           be specified.
EOF
			exit 0
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

		-P|--no-portable)
			_deployPortable=false
			;;

		-r|--dir)
			if [ -z "$2" ]; then
				logError "Missing value for $1 option!"
				_hasErrors=true
			else
				_destinationDir="$2"
			fi
			shift
			;;

		-s|--start)
			_startStack=true
			;;

		-v|--version)
			logLine "$MY_VERSION"
			exit 0
			;;

		--)	# Optional explicit end of options
			shift
			break
			;;

		-*)
			logError "Unknown option:  $1"
			_hasErrors=true
			;;

		*)	# Implicit end of options
			break;
			;;
	esac
	shift
done

# Any remaining arguments are hosts to deploy to
if [ $# -gt 0 ]; then
	_deployToHosts=("$@")
fi

# There must be at least one deploy host
if [ ${#_deployToHosts[@]} -eq 0 ]; then
	logError "At least one deployment HOST must be specified!"
	_hasErrors=true
fi

# Bail if there are any errors
if $_hasErrors; then
	exit 1
fi

# Identify whether there are any new images to deploy
imageIDFile="${_imagesDirectory}/LAST-SAVED-IMAGE-IDS.txt"
if $_deployPortable; then
	if [ ! -f "$imageIDFile" ]; then
		logWarning "Image deployment requested, but no image ID file found at ${imageIDFile}.  To suppress this warning, disable portable deployment or build the image(s) to ${_imagesDirectory}." >&2
		_deployPortable=false
	fi
fi

# Build a temporary filesystem to hold the Docker Compose file and other files
virtualRootDir=$(mktemp -d)
virtualLibDir="${virtualRootDir}/lib"
virtualDockerDir="${virtualRootDir}/docker"
mkdir -p "$virtualDockerDir"
trap "rm -rf ${virtualRootDir}" EXIT
cp "${PROJECT_DIRECTORY}/compose.sh" "${virtualRootDir}/" 2>/dev/null
cp "${PROJECT_DIRECTORY}/{start,start-*}.sh" "${virtualRootDir}/" 2>/dev/null
cp "${PROJECT_DIRECTORY}/{stop,stop-*}.sh" "${virtualRootDir}/" 2>/dev/null
cp -r "${PROJECT_DIRECTORY}/lib" "${virtualLibDir}/"

# Allow the user to copy an entire directory en-masse to the remote host
if [ -d "${PROJECT_DIRECTORY}/deploy.d" ]; then
	cp -r "${PROJECT_DIRECTORY}/deploy.d/"* "${virtualRootDir}/"
fi

# Remove all Git tracking files from the virtual filesystem
find "${virtualRootDir}" -name '.git*' -exec rm -rf {} \;

# Identify the Docker Compose override files to use
overrideComposeFile="${DOCKER_DIRECTORY}/docker-compose.${_deployStage}.yaml"
if [ ! -f "$overrideComposeFile" ]; then
	overrideComposeFile=
fi

# Bake the Docker Compose configuration file into the temporary, virtual
# directory structure.  The baked file MUST be named "docker-compose.yaml" for
# Docker Compose to find it.
logLine "Baking the Docker Compose configuration file..."
bakedComposeFile="${virtualDockerDir}/docker-compose.yaml"
dynamicBakeComposeFile "$bakedComposeFile" "$_deployStage" "$DOCKER_DIRECTORY"
if [ 0 -ne $? ]; then
	noBakeErrorMessage="Unable to bake ${COMPOSE_BASE_FILE}"
	if [ -n "$overrideComposeFile" ]; then
		noBakeErrorMessage+=" with ${overrideComposeFile}"
	fi
	noBakeErrorMessage+="!"
	logError "$noBakeErrorMessage"
	exit 3
fi

# Remove all build contexts and profiles from the baked configuration
logLine "Removing build contexts and service profiles from the baked Docker Compose configuration file..."
yaml-set --nostdin --delete --change='services.*.build' "$bakedComposeFile" 2>/dev/null
yaml-set --nostdin --delete --change='services.*.profiles' "$bakedComposeFile" 2>/dev/null

# Deploy to each host
for deployToHost in "${_deployToHosts[@]}"; do
	logInfo "Deploying to ${deployToHost}..."

	# Ensure the destination directory exists and is owned by the Docker group
	logLine "Ensuring the remote deployment directory exists..."
	silentSsh "${deployToHost}" <<-EOC
		if [ -d "${_destinationDir}" ]; then
			cd "$_destinationDir"
			# Stop the Docker Compose stack, preserving the volumes
			if [ -f "${_destinationDir}/stop.sh" ]; then
				"${_destinationDir}"/stop.sh --stage ${_deployStage}
			elif [ -f "${_destinationDir}/compose.sh" ]; then
				"${_destinationDir}"/compose.sh \
					--stage ${_deployStage} \
					down --remove-orphans --rmi all
			elif [ -f "${_destinationDir}/docker-compose.yaml" ]; then
				# Stop and delete the stack except for its volume(s)
				docker compose -f "${_destinationDir}/docker-compose.yaml" \
					down --remove-orphans --rmi all
			else
				docker compose \
					down --remove-orphans --rmi all
			fi
			if [ 0 -ne \$? ]; then
				echo "ERROR:  Unable to stop the stack!  Please stop it and destroy or move ${_destinationDir}." >&2
				exit 127
			fi
			# Preserve the old directory by adding a datetime stamp suffix
			if ! mv "${_destinationDir}" "${_destinationDir}.\$(date +%Y%m%d-%H%M%S.%N)"
			then
				echo "ERROR:  Failed to backup ${_destinationDir} on ${deployToHost}!" >&2
				exit 1
			fi
		fi
		mkdir -p "${_destinationDir}" && \
			chgrp ${_dockerGroup} "${_destinationDir}" && \
			chmod 0770 "${_destinationDir}"
		exit \$?
EOC
	if [ 0 -ne $? ]; then
		logError "Deployment to ${_destinationDir} failed on ${deployToHost}!" >&2
		exit 2
	fi

	# Copy the virtual filesystem to the remote host
	logLine "Copying files to ${deployToHost}..."
	scp -r "$virtualRootDir"/* "${deployToHost}":${_destinationDir}/
	if [ 0 -ne $? ]; then
		logError "Failed to copy source files to ${deployToHost}:${_destinationDir}" >&2
		exit 3
	fi

	# Fix permissions on the new files and optionally start the service stack
	logText="Fixing permissions on ${deployToHost}:${_destinationDir}"
	if $_startStack; then
		logText+=" and starting the service stack"
	else
		logText+=" but leaving the service stack DOWN (be sure to run ${_destinationDir}/start.sh)"
	fi
	logText+="..."
	logLine "$logText"
	silentSsh "${deployToHost}" <<-EOC
		chgrp -R ${_dockerGroup} "${_destinationDir}" && \
			find "${_destinationDir}" -type d -exec chmod 0770 {} \; && \
			find "${_destinationDir}" -type f -exec chmod 0660 {} \; && \
			find "${_destinationDir}" -type f -name '*.sh' -exec chmod 0770 {} \;
		if [ 0 -ne \$? ]; then
			exit 1
		fi
		if $_startStack; then
			cd "${_destinationDir}"
			./start.sh --stage ${_deployStage}
		fi
		exit \$?
EOC
	if [ 0 -ne $? ]; then
		logText="Failed to fix permissions on ${deployToHost}:${_destinationDir}"
		if $_startStack; then
			logText+=" or start the service stack"
		fi
		logText+="!"
		logError "$logText"
		exit 4
	fi

	# Everything beyond this point is for deploying images
	if ! $_deployPortable; then
		continue
	fi

	# Copy the image file(s) and register them on the remote host
	while IFS=$'\a' read -r imageRef imageID imageFile; do
		imageName=${imageRef%%:*}
		shortFileName=$(basename "$imageFile")
		destinationFile="${_destinationDir}/${shortFileName}"

		logLine "Copying ${imageFile} to ${deployToHost}..."
		scp "$imageFile" "${deployToHost}":${_destinationDir}/

		logLine "Registering ${imageName} on ${deployToHost}..."
		silentSsh "${deployToHost}" <<-EOR
			docker load -i ${destinationFile} \
				&& docker image tag ${imageID} ${imageName}:latest \
				&& rm -f ${destinationFile}
			exit $?
EOR
		if [ 0 -ne $? ]; then
			logError "Failed to register ${destinationFile} on ${deployToHost}!" >&2
			exit 5
		fi
	done < <(tr \\t \\a <"$imageIDFile")
done
