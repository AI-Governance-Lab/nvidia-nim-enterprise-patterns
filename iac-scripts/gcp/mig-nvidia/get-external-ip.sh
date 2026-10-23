#!/usr/bin/env bash
set -euo pipefail

curl --fail --silent --show-error --max-time 10 https://api.ipify.org
printf '\n'
