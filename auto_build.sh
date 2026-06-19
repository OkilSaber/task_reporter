#!/bin/bash
set -uo pipefail
flutter clean

# Launch both builds in the background. `bash <script>` works even though
# linux_build.sh has no shebang line. `$!` is the most recent job's PID.
bash macos_build.sh &
pid_macos=$!

bash linux_build.sh &
pid_linux=$!

# `wait <pid>` returns that job's exit status, so we can report each one.
wait "$pid_macos"; status_macos=$?
wait "$pid_linux"; status_linux=$?

echo "[parallel] macos_build.sh exited $status_macos"
echo "[parallel] linux_build.sh exited $status_linux"

# Fail the script if either build failed.
if [ "$status_macos" -ne 0 ] || [ "$status_linux" -ne 0 ]; then
  exit 1
fi
