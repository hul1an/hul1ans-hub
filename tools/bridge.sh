#!/bin/sh
# usage: bridge.sh '{"op":"children","path":["Workspace"],"depth":2}' [timeout in seconds]
folder="$LOCALAPPDATA/Potassium/workspace/claude-bridge"
timeout=${2:-30}

# written under another name and renamed so the bridge never reads half a file
printf '%s' "$1" > "$folder/request.tmp"
mv "$folder/request.tmp" "$folder/request.json"

waited=0
while [ -e "$folder/request.json" ]; do
	if [ "$waited" -ge $((timeout * 10)) ]; then
		rm -f "$folder/request.json"
		echo "no answer in $timeout s, is the bridge running?" >&2
		exit 1
	fi
	sleep 0.1
	waited=$((waited + 1))
done
cat "$folder/response.txt"
