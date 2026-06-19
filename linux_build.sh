#!/bin/bash

rm -rf build_linux
rm -rf build_linux.zip

# 1. Enable QEMU multi-architecture support in Docker
docker run --privileged --rm tonistiigi/binfmt --install all

# 2. Build for Intel/AMD Linux (will run under emulation, taking longer)
docker build --platform linux/amd64 -t task-reporter-builder-amd64 -f Dockerfile.linux .

# 3. Run container and copy bundle
docker run -d --name builder-amd64 --platform linux/amd64 task-reporter-builder-amd64 tail -f /dev/null
docker cp builder-amd64:/app/build/linux/x64/release/bundle/ ./build_linux
docker rm -f builder-amd64
# make a zip
zip -r build_linux.zip build_linux/
