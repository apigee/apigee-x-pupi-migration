#!/usr/bin/env bash
#
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#shellcheck source=/dev/null
#shellcheck disable=SC2154,SC2181
SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers.sh" || exit 1

function usage {
echo """
#**
# This action is to check the status of the Apigee operation periodically
# and wait for it to completion.
#
# Usage:
#     bash ${0} -o|--op <OPERATION_ID> [-t|--sleeptime <SLEEP_SECONDS>]
#         where, 'OPERATION_ID' is the Apigee Operation ID.
#                'SLEEP_SECONDS' is the wait time in seconds before rechecking
#                    the status of the Apigee Operation. Defaults to 30 seconds.
# Examples:
# To check the status of operation '51b915cc-7ddd-4402-b52c-90de0d1bb785' every 30 seconds (default).
#     bash ${0} -o 51b915cc-7ddd-4402-b52c-90de0d1bb785
#
# To check the status of operation '51b915cc-7ddd-4402-b52c-90de0d1bb785' every 10 seconds,
#     bash ${0} -o 51b915cc-7ddd-4402-b52c-90de0d1bb785 -t 10
#**
"""
exit 1
}

#################### ~ MAIN STARTS HERE ~ ####################

# Process input parameters.
[[ $# -eq 0 ]] && usage
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -o|--op)        OP_ID=$2;     shift  ;;
    -t|--sleeptime)  SLEEP_TIME=$2; shift  ;;
    *)              usage                ;;
  esac
  shift
done

[[ -z "${OP_ID}" ]] && logerr "missing Apigee Operation ID. Exiting." && usage
[[ ${SLEEP_TIME} -le 0 ]] && SLEEP_TIME=30

wait_for_operation "${OP_ID}" "${SLEEP_TIME}"
