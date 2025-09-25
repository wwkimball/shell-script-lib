################################################################################
# Define functions for colorized console logging.
#
# This script provides functions to output messages in different colors
# to the console, making it easier to distinguish between different types of
# messages (info, debug, error, warning).
#
# The following environment variables are used to control the behavior of these
# functions:
#   - LOG_LEVEL:  Can be used to increase logging verbosity.  All normal,
#     warning, and error messages are always output.  The following additional
#     logging levels are supported:
#     - VERBOSE:  Verbose messages.
#     - DEBUG:  Debugging (and verbose) information.
#
# Copyright 2001, 2018, 2024, 2025 William W. Kimball, Jr., MBA, MSIS
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

# Avoid repeated loading of this library
if [ -n "${__LIB_LOGGER_LOADED:-}" ]; then
	return 0
fi
__LIB_LOGGER_LOADED=true

# Set the default logging level
if [ -z "${LOG_LEVEL:-}" ]; then
	LOG_LEVEL="INFO"
fi

# Do not colorize text when output is redirected to a file or pipe
[ -t 1 ] || export TERM=dumb

# Check whether tput is available
_hasTput=true
if ! command -v tput &>/dev/null; then
	_hasTput=false
else
	# The tput command is available but does it have color definitions?
	if ! tput colors &>/dev/null; then
		_hasTput=false
	fi
fi

# Define terminal-sensitive color codes
_colBlue=''
_colDarkGray=''
_colLightRed=''
_colLightGreen=''
_colLightYellow=''
_colLightMagenta=''
_colEnd=''
if [ "$TERM" != "dumb" ]; then
	if $_hasTput; then
		_colBlue=$(tput setaf 4)
		_colDarkGray=$(tput setaf 8)
		_colLightRed=$(tput setaf 9)
		_colLightGreen=$(tput setaf 10)
		_colLightYellow=$(tput setaf 11)
		_colLightMagenta=$(tput setaf 13)
		_colEnd=$(tput sgr0)
	else
		# Without tput, fallback to ANSI escape codes
		_colBlue='\033[0;34m'
		_colDarkGray='\033[0;90m'
		_colLightRed='\033[0;91m'
		_colLightGreen='\033[0;92m'
		_colLightYellow='\033[0;93m'
		_colLightMagenta='\033[0;95m'
		_colEnd='\033[00m'
	fi
fi
readonly _colBlue _colDarkGray _colLightRed _colLightGreen \
	_colLightYellow _colLightMagenta _colEnd

###
# Echos a string in a color.
##
function _echoInColor {
	local echoColor echoMessage
	echoColor=$1
	shift
	echo -en "${echoColor}${@}${_colEnd}"
}

###
# Prints a colored ERROR prefix.
##
function _echoPrefixError {
	echo -e "$(_echoInColor $_colLightRed 'ERROR: ')"
}

###
# Prints a colored WARNING prefix.
##
function _echoPrefixWarning {
	echo -e "$(_echoInColor $_colLightYellow 'WARNING: ')"
}

###
# Prints a colored INFO prefix.
##
function _echoPrefixInfo {
	echo -e "$(_echoInColor $_colLightGreen 'INFO: ')"
}

###
# Prints a colored verbose INFO prefix.
##
function _echoPrefixVerbose {
	echo -e "$(_echoInColor $_colBlue 'INFO: ')"
}

###
# Prints a colored DEBUG prefix.
##
function _echoPrefixDebug {
	echo -e "$(_echoInColor $_colLightMagenta 'DEBUG: ')"
}

###
# Stops any previous colorization and prints a line of text with the default
# color.
##
function logLine {
	echo -e "${_colEnd}$@"
}

###
# Prints an ERROR message
##
function logError {
	echo -e "$(_echoPrefixError) $@" >&2
}

###
# Prints a WARNING message
##
function logWarning {
	echo -e "$(_echoPrefixWarning) $@"
}

###
# Prints a WARNING message to the ERROUT stream
##
function logWarningToError {
	echo -e "$(_echoPrefixWarning) $@" >&2
}

###
# Prints an INFO message
##
function logInfo {
	echo -e "$(_echoPrefixInfo) $@"
}

###
# Prints a verbose-only INFO message
##
function logVerbose {
	if [ "$LOG_LEVEL" == "VERBOSE" ] || [ "$LOG_LEVEL" == "DEBUG" ]; then
		echo -e "$(_echoPrefixVerbose) $@"
	fi
}

###
# Prints an DEBUG message
##
function logDebug {
	if [ "$LOG_LEVEL" == "DEBUG" ]; then
		echo -e "$(_echoPrefixDebug) $@"
	fi
}

###
# Prints an DEBUG message to STDERR
##
function logDebugToError {
	if [ "$LOG_LEVEL" == "DEBUG" ]; then
		echo -e "$(_echoPrefixDebug) $@" >&2
	fi
}

###
# Prints and ERROR message and abends the process with an exit code
##
function errorOut {
	local errorCode=${1:-1}
	shift
	logError $@
	exit $errorCode
}

###
# Prints a horizontal line comprised of a given character
##
function logCharLine {
	local repeatCharacter=${1:0:1}
	local colorCode=${2:-$_colDarkGray}
	local lineWidth writeLine

	# When no character is provided, use a hyphen
	if [ -z "$repeatCharacter" ]; then
		repeatCharacter="-"
	fi

	# Prefer tput for terminal width
	if $_hasTput; then
		# Get the terminal width using tput
		lineWidth=$(tput cols)
	else
		# Fallback to default width if tput is not available
		lineWidth=${COLUMNS:-80}
	fi

	# Construct the output line
	writeLine=$(printf "%-${lineWidth}s" "${repeatCharacter}" | tr " " "${repeatCharacter}")

	# Print the line
	echo -e "${colorCode}${writeLine}${_colEnd}"
}
