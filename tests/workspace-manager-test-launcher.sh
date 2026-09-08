#!/bin/bash

set -euo pipefail

app_id=$1
title=$2
cwd=$3

exec foot --app-id="$app_id" --title="$title" --working-directory="$cwd" sh -c 'sleep 30'
