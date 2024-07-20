#!/bin/bash
###############################################################################
# Reset glboal SSH Host Keys for all known SCM services.
#
# Copyright 2023 William W. Kimball, Jr., MBA, MSIS
# All rights reserved.
###############################################################################
declare -a sshHosts=(github.com bitbucket.org)
sharedHostsFile=/etc/ssh/ssh_known_hosts

# Start by deleting all old keys from the central SSH service and every
# user's personal files.  This will change ownership of the file to root.
echo -e "\nDeleting old SSH Host keys..."
for sshHost in "${sshHosts[@]}"; do
	sshHostIP=$(getent hosts "$sshHost" | cut -d' ' -f1)
	echo -e "\n${sshHost} is AKA ${sshHostIP}."

	for hostFile in \
			"$sharedHostsFile" \
			/root/.ssh/known_hosts \
			/home/*/.ssh/known_hosts \
			/var/lib/jenkins/.ssh/known_hosts \
			/var/jenkins_home/.ssh/known_hosts
	do
		if [ ! -f "$hostFile" ]; then
			echo "Skipping nonexistent ${hostFile}..."
			continue
		fi
		echo "Deleting old SSH Host keys from ${hostFile}..."
		ssh-keygen -f "$hostFile" -R "$sshHost" 2>/dev/null
		ssh-keygen -f "$hostFile" -R "$sshHostIP" 2>/dev/null
		echo
	done
done

# Repair broken user ownership and permissions of the personal known_hosts
# files.
echo -e "\nFixing ownership of personal known_hosts files..."
for userDir in /home/* /var/lib/*; do
	userName=$(basename "$userDir")
	userKnownHostsFile="${userDir}/.ssh/known_hosts"
	if [ -f "$userKnownHostsFile" ]; then
		echo "Fixing ${userKnownHostsFile}..."
		chown "${userName}:${userName}" "$userKnownHostsFile"
		chmod 0600 "$userKnownHostsFile"
		echo
	fi
done

# Then, add the known SCM hosts only to the central SSH service
echo -e "\nAdding new SSH Host keys to ${sharedHostsFile}..."
for sshHost in "${sshHosts[@]}"; do
	if ! ssh-keyscan -t rsa "$sshHost" >>"$sharedHostsFile"; then
		echo "Failed to add ${sshHost} to ${sharedHostsFile}!"
		exit 3
	fi
done
chmod 0644 "$sharedHostsFile"
