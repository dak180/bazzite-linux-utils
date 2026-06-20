#!/usr/bin/env bash
# shellcheck disable=SC2155,2086,2001

# Global Vars
guiName=""
shareName=""
mountPoint=""
mountPath=""
sharePath=""
absolutePath=""
serverName=""
userName=""
credsFile=""
uUID=""
uGID=""

# Functions
function mountFile() {
	sudo tee "/etc/systemd/system/${shareName}.mount" > /dev/null << EOF
[Unit]
Description=Mount ${shareName} on ${serverName}
# A human-readable description of this mount unit.

# Ensures the network is available before trying to mount.
Requires=network-online.target
# This unit will only start if 'network-online.target' is available.
After=network-online.target systemd-resolved.service
# Waits until network and DNS resolution are ready.
Wants=network-online.target systemd-resolved.service
# Suggests that these services should be running, but does not fail if they aren't.

[Mount]
# Defines what to mount and where.

# The network share (SMB/CIFS) that will be mounted.
What=//${serverName}/${sharePath}

# Local mount point where the share will be attached.
Where=${absolutePath}

# Specifies the filesystem type.
Type=cifs
# This is necessary for mounting a Windows SMB/CIFS share.

# Mount options:
Options=rw,uid=${uUID},gid=${uGID},nofail,iocharset=utf8,nounix,noserverino,soft,credentials=${credsFile},x-gvfs-name=${guiName},vers=3
# 'rw'           Read/write access.
# 'uid=1000'     Ensures that the mounted files are owned by user ID 1000 (your main user).
# 'gid=1000'     Ensures group ownership by group ID 1000.
# 'nofail'       Prevents boot failure if the SMB share is unavailable.
# 'credentials=/var/home/<username>/.smb/credentials'  Specifies the file storing the SMB username & password.
# 'vers=3'     Forces SMB version 3.0 or later for security and performance.

# Sets a timeout to stop trying if the mount hangs.
TimeoutSec=30
# If the mount attempt takes longer than 30 seconds, it will give up.

[Install]
# Ensures this mount is activated at boot.
WantedBy=multi-user.target
# Mounts the share when the system reaches multi-user mode (normal operation).
EOF

	sudo chown root:root "/etc/systemd/system/${shareName}.mount"
	sudo chmod u=rw,g=r,o=r "/etc/systemd/system/${shareName}.mount"
}

function automountFile() {
	sudo tee "/etc/systemd/system/${shareName}.automount" > /dev/null << EOF
[Unit]
Description=Automount ${shareName} on ${serverName}

[Automount]
Where=${absolutePath}
TimeoutIdleSec=300

[Install]
WantedBy=multi-user.target
EOF

	sudo chown root:root "/etc/systemd/system/${shareName}.automount"
	sudo chmod u=rw,g=r,o=r "/etc/systemd/system/${shareName}.automount"
}

function credFile() {
	mkdir -p "$(dirname "${credsFile}")"

	tee "${credsFile}" > /dev/null << EOF
username=${userName}
password=

EOF

	clear -x
	cat > "/dev/stderr" << EOF
We are about open credentials file for you to enter the password for the server.
EOF
	sudo chmod 600 "${credsFile}"
	sudo chown root:root "${credsFile}"

	if ! read -n1 -rsp $'Press any key to continue or ctrl+c to exit.\n'; then
		exit 1
	fi

	sudo ${EDITOR:-nano} "${credsFile}"
}

function selinuxCheck() {
	if command -v getenforce &> /dev/null && [ "$(getenforce)" = "Enforcing" ]; then
		sudo restorecon -v "/etc/systemd/system/${shareName}.automount"
		sudo restorecon -v "/etc/systemd/system/${shareName}.mount"
	fi
	sudo systemctl daemon-reload
#	sudo systemctl enable "${shareName}.mount"
	sudo systemctl enable "${shareName}.automount"
	sudo systemctl start "${shareName}.automount"
}

function inputSan() {
	local input="${1#smb://}"

	input="$(sed -e "s:^[[:blank:]]*::" -e "s:[[:space:]]*$::" -e 's:/*$::' <<< "${input}")"
	if [[ "${input}" != */* ]]; then
		echo "No share name found" >&2
		return 1
	fi
	sharePath="${input#*/}"

	: "${guiName:=${sharePath}}"
	guiName="$(echo -n "${guiName}" | jq -sRr @uri)"

	if [ -z "${mountPath}" ]; then
		: "${mountPath:=/media}"
	elif [ ! -d "${mountPath}" ]; then
		echo "Not a valid mount path" >&2
		return 1
	else
		mountPath="$(sed -e 's:/*$::' <<< "${mountPath}")"
	fi


	local userTest="$(cut -d '/' -f '1'  <<< "${input}")"

	if [[ "${userTest}" =~ [[:blank:]] ]]; then
		echo "Invalid server address / user name: whitespace detected" >&2
		return 1
	fi


	if [[ "${userTest}" =~ @ ]]; then
		userName="$(cut -d '@' -f '1' <<< "${userTest}")"
		serverName="$(cut -d '@' -f '2' <<< "${userTest}")"
	else
		: "${userName:="$(id -un)"}"
		serverName="${userTest}"
	fi
	credsFile="${HOME}/.smb/$(sed -e 's:[^A-Za-z0-9._]:_:g' <<< "${userName}-${serverName}")"

	mountPoint="$(sed -e 's:[^A-Za-z0-9._]:_:g' <<< "${userName}_${serverName}_${sharePath}")"

	if [ "${RESOLVER}" = "realpath" ]; then
	# make the mount point if required
	mkdir -p "${mountPath}/${mountPoint}"
	fi
	absolutePath="$(${RESOLVER} "${mountPath}/${mountPoint}")"

	shareName="$(systemd-escape -p "${absolutePath}")"

	if [ -z "${userName}" ] || [ -z "${serverName}" ] || [ -z "${sharePath}" ]; then
		return 1
	fi
}


# Check if needed software is installed.
PATH="${PATH}:/usr/local/sbin:/usr/local/bin"
commands=(
grep
sed
cut
sudo
dirname
chmod
chown
systemd-escape
systemctl
id
tee
mkdir
cat
readlink
jq
)
for command in "${commands[@]}"; do
	if ! command -v "${command}" &> /dev/null; then
		if [ "${command}" = "readlink" ] && command -v "realpath" &> /dev/null; then
			RESOLVER="realpath"
			continue
		fi
		echo "${command} is missing, please install" >&2
		exit 100
	elif [ "${command}" = "readlink" ]; then
		if readlink -f / &> /dev/null; then
			RESOLVER="readlink -f"
			continue
		elif command -v "realpath" &> /dev/null; then
			RESOLVER="realpath"
			continue
		else
			echo "${command} is missing, please install" >&2
			exit 100
		fi
	fi
done

sudo -v # ask for sudo password up-front
while true; do
  # Update user's timestamp without running a command
  sudo -nv; sleep "60"
  # Exit when the parent process is not running any more. In fact this loop
  # would be killed anyway after being an orphan (when the parent process
  # exits). But this ensures that and probably exits sooner.
  kill -0 $$ 2>/dev/null || exit
done &
keepalive_pid="$!"
trap 'kill ${keepalive_pid} 2>/dev/null' EXIT


#
# Main Script Starts Here
#


# Gather non interactive info
uUID="$(id -u)"
uGID="$(id -g)"

# Start interactive prompts
cat > "/dev/stderr" << EOF
Enter the share you want to connect to in the following format:
smb://[user@]server_or_ipv4/share
EOF
read -rp $'> ' usrInput
if [[ ! "${usrInput}" = smb://* ]]; then
	echo "Not valid input" > "/dev/stderr"
	exit 1
fi

cat > "/dev/stderr" << EOF
Enter the mount path you want to use in the following format:
/path/to/use
EOF
read -rp $'[/media]> ' mountPath

cat > "/dev/stderr" << EOF
Enter the name you want the share to use in the gui
EOF
read -rp $'> ' guiName


inputSan "${usrInput}" || { echo "Not valid input" > "/dev/stderr"; exit 1; }

# User validation
cat > "/dev/stderr" << EOF
Based on your input we will be connecting to ${serverName} as ${userName} using the password that will be stored in ${credsFile} to map the share ${sharePath} to ${mountPath}/${mountPoint}.
Does all this look correct?
EOF

if ! read -n1 -rsp $'Press any key to continue or ctrl+c to exit.\n'; then
		exit 1
	fi


credFile

mountFile

automountFile

selinuxCheck

