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
# This action is to attach / detach all the environments to Apigee Instance  for
# the given region. The environments should be listed at 'ENVIRONMENTS_LIST'
# variable in 'source.sh'.
#
# Usage:
#     bash ${0} -r|--region <REGION> [--attach|--detach]
#         where, 'REGION' is the runtime region of the Apigee Instance.
#                '--attach' will attach all the environments to the Apigee Instance in the given region.
#                '--detach' will detach all the environments from the Apigee Instance in the given region.
#
# Examples:
# To attach all Environments to 'us-east1' Apigee Instance,
#     bash ${0} -r us-east1 --attach
#
# To detach all Environments from 'us-east1' Apigee Instance,
#     bash ${0} -r us-east1 --detach
#**
"""
exit 1
}

# attach_environments attaches all the environments to the Apigee Instance of given region.
function attach_environments {
  for env in $(echo "${ENVIRONMENTS_LIST}" | tr ',' '\n');
  do
    payload='{
        "environment":"'"${env}"'"
      }'
    log "associating environment '${env}' to apigee instance '${INSTANCE_NAME}' in region '${RUNTIME_LOCATION}'."

    setup_curl
    status_code=$(ACURL -X POST "${PROJECT_URL}/instances/${INSTANCE_NAME}/attachments" \
      -H "Content-Type:application/json" \
      -d "${payload}")
    if [[ "${status_code}" == "409" ]]; then
      log "environment '${env}' is already attached with apigee instance '${INSTANCE_NAME}'."
      continue
    elif [[ "${status_code}" != "200" ]]; then
      logerr "failed to attach environment '${env}' to apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
      return 1
    fi

    log "successfully scheduled environment attachment job for apigee instance '${INSTANCE_NAME}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'"
    attach_op_id=$(jq -r .name "${CURL_DATA_FILE}" | rev | cut -d '/' -f1 | rev)
    wait_for_operation "${attach_op_id}" "${op_sleep_time}" || return 1
  done

  log "successfully attached all the environment to apigee instance '${INSTANCE_NAME}'."
  return 0
}

# detach_environments removes all the environments from the Apigee Instance of given region.
function detach_environments {
  setup_curl
  status_code=$(ACURL -X GET "${PROJECT_URL}/instances/${INSTANCE_NAME}/attachments")
  if [[ "${status_code}" != "200" ]]; then
    logerr "unable to list environment attachments to apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi
  attachments_list=$(jq -c . "${CURL_DATA_FILE}")
  for env in $(echo "${ENVIRONMENTS_LIST}" | tr ',' '\n');
  do
    att_name=$(echo "${attachments_list}" | jq -r ".attachments[] | select(.environment=\"${env}\") | .name" 2>/dev/null)
    if [[ -z "${att_name}" ]]; then
      log "environment '${env}' is not attached to the apigee instance '${INSTANCE_NAME}' in region '${RUNTIME_LOCATION}'."
      continue
    fi

    log "detaching environment '${env}' from apigee instance '${INSTANCE_NAME}' in region '${RUNTIME_LOCATION}'. Attachment name: '${att_name}'."
    setup_curl
    status_code=$(ACURL -X DELETE "${PROJECT_URL}/instances/${INSTANCE_NAME}/attachments/${att_name}")
    if [[ "${status_code}" != "200" ]]; then
      logerr "failed to detach environment '${env}' from apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
      return 1
    fi
  done

  log "successfully detached all the environment from apigee instance '${INSTANCE_NAME}'."
  return 0
}

#################### ~ MAIN STARTS HERE ~ ####################

# Process input parameters.
[[ $# -eq 0 ]] && usage
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -r|--region)  REGION=$2;    shift ;;
    --attach)       ATTACH=true;        ;;
    --detach)       DETACH=true;        ;;
    *)              usage               ;;
  esac
  shift
done

if [[ "${ATTACH}" == "${DETACH}" ]]; then
  logerr "incorrect flag. provide either '--attach' or '--detach'."
  usage
fi

init_region "${REGION}" || exit 1

# Global variables.
op_sleep_time=60 # Wait time in seconds before rechecking operation status.
attach_op_id=""


if [[ -z "${ENVIRONMENTS_LIST}" ]]; then
  logerr "empty 'ENVIRONMENTS_LIST' variable in region '${RUNTIME_LOCATION}'."
  exit 1
fi

# Attach environment flow.
if [[ "${ATTACH}" == true ]]; then
    attach_environments || exit 1
    exit 0
fi

# Detach environment flow.
if [[ "${DETACH}" == true ]]; then
    prompt "Do you want to continue with detaching environments from apigee instance in region '${REGION}'" \
      || { logerr "Cancelling request. Exiting." && exit 1; }
    detach_environments || exit 1
    exit 0
fi
