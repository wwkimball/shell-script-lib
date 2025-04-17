#!/bin/bash
################################################################################
# Define functions for colorized console logging.
#
# This script provides functions to output messages in different colors
# to the console, making it easier to distinguish between different types of
# messages (info, debug, error, warning).
################################################################################
# Libraries must not be directly executed
if [ -z "${BASH_SOURCE[1]}" ]; then
	echo "ERROR:  Attempt to directly execute $0." >&2
	exit 1
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

# Define constants for color codes
COLOR_RESET=""
COLOR_BRIGHT_WHITE=""
COLOR_GREY=""
COLOR_BRIGHT_RED=""
COLOR_BRIGHT_YELLOW=""
if [ "$TERM" != "dumb" ]; then
	if $_hasTput; then
		COLOR_RESET=$(tput sgr0)
		COLOR_BRIGHT_WHITE=$(tput setaf 15)
		COLOR_GREY=$(tput setaf 8)
		COLOR_BRIGHT_RED=$(tput setaf 9)
		COLOR_BRIGHT_YELLOW=$(tput setaf 11)
	else
		# Without tput, fallback to ANSI escape codes
		COLOR_RESET="\e[0m"
		COLOR_BRIGHT_WHITE="\e[1;37m"
		COLOR_GREY="\e[1;30m"
		COLOR_BRIGHT_RED="\e[1;31m"
		COLOR_BRIGHT_YELLOW="\e[1;33m"
	fi
fi
readonly COLOR_RESET COLOR_BRIGHT_WHITE COLOR_GREY COLOR_BRIGHT_RED \
	COLOR_BRIGHT_YELLOW

# Function to output plain text (no color)
function logline {
	echo -e "${COLOR_RESET}$*"
}

# Function to output bright white text (info line)
function infoline {
	echo -e "${COLOR_BRIGHT_WHITE}INFORMATION:  $*${COLOR_RESET}"
}

# Function to output grey text (debug line)
function debugline {
	echo -e "${COLOR_GREY}DEBUG:  $*${COLOR_RESET}"
}

# Function to output bright red text (error line)
function errorline {
	echo -e "${COLOR_BRIGHT_RED}ERROR:  $*${COLOR_RESET}" >&2
}

# Function to output bright yellow text (warning line)
function warnline {
	echo -e "${COLOR_BRIGHT_YELLOW}WARNING:  $*${COLOR_RESET}"
}

# Function to repeat a string across the terminal width
function lineline {
	local repeatCharacter=${1:0:1}
	local colorCode=${2:-$COLOR_GREY}
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
	echo -e "${colorCode}${writeLine}${COLOR_RESET}"
}
