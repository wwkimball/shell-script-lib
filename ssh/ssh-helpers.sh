###############################################################################
# Define shell helper functions for use with Docker Compose.
###############################################################################

###
# Send commands to a remote host via SSH without displaying the output.
#
# From:  https://serverfault.com/a/764403
##
function silentSsh {
	local connectionString="$1"
	local commands="$2"
	if [ -z "$commands" ]; then
		commands=`cat`
	fi
	ssh -T $connectionString "$commands"
}
