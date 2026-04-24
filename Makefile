SHELL := /usr/bin/env bash

.PHONY: all down download download-artifacts firmware-artifacts

all: down

down:
	./download_firmware_artifacts.sh

download: down

download-artifacts: down

firmware-artifacts: down
