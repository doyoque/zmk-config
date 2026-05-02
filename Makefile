SHELL := /usr/bin/env bash

.PHONY: all down download download-artifacts firmware-artifacts

all: down

down:
	./artifact.sh

download: down

download-artifacts: down

firmware-artifacts: down
