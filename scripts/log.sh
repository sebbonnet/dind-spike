#!/usr/bin/env bash
set -e

function log {
    local message=$1
    local datetime=$(date +"%Y-%m-%dT%T")
    echo "[Dind build] $datetime: $message"
}
