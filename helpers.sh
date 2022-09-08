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
#shellcheck disable=SC2154
shopt -s expand_aliases
SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/source.sh" || exit 1

function log() {
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [info] fn(${FUNCNAME[1]}) :: $*"
}

function logerr() {
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [error] fn(${FUNCNAME[1]}) :: $*" 1>&2;
}

function prompt() {
  echo
  read -r -p "==> $1 (y/n)? " yn
  while true; do
    case $yn in
      [Yy]* ) return 0  ;;
      [Nn]* ) return 1  ;;
      *) read -r -p "Please enter 'y' or 'n': " yn
    esac
  done
}

# setup_curl set up alias for CURL to return http status code and
# prints the response to the file output.
function setup_curl {
  CURL_DATA_FILE="${SCRIPT_DIR}/_response.txt"
  rm -f "${CURL_DATA_FILE}" && touch "${CURL_DATA_FILE}"
  alias ACURL="curl -H \"\${AUTH}\" -s -o \"\${CURL_DATA_FILE}\" -w '%{http_code}'"
  PROJECT_URL="https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}"
  export ACURL PROJECT_URL CURL_DATA_FILE
}

# init_region initializes the variables for the given region.
# It sources the function `INIT_REGION_<REGION>` in the `source.sh`.
function init_region {
  region=${1:?region is required for initializing properties}
  fn_region=$(echo "${region}" | awk '{print toupper($0)}' | tr '-' '_')
  log "loading properties for the region '${region}' from 'INIT_REGION_${fn_region}'."
  INIT_REGION_"${fn_region}"
  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    logerr "failed to load the properties for region '${region}'."
    return 1;
  fi

  if [[ "${region}" != "${RUNTIME_LOCATION}" ]]; then
    logerr "failed to load the properties for region '${region}'. mismatch in RUNTIME_LOCATION: '${RUNTIME_LOCATION}'."
    return 1
  fi

  log "successfully loaded properties for region '${RUNTIME_LOCATION}'."

  get_organization || return 1
  return 0
}

# get_organization gets the Apigee organization to ensure valid authn/z.
function get_organization {
  setup_curl
  status_code=$(ACURL -X GET "${PROJECT_URL}" 2>&1)
  if [[ "${status_code}" != "200" ]]; then
    logerr "failed to get the apigee organization '${PROJECT_ID}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi
  log "successfully fetched apigee organization '${PROJECT_ID}'."
  return 0
}

# wait_for_operation checks the status of the Apigee operation periodically, and
# waits for the completion.
function wait_for_operation {
  apigee_op_id="${1}"
  op_sleep_time="${2}"
  [[ -z "${apigee_op_id}" ]] && logerr "missing apigee operation id. Exiting." && return 1
  [[ ${op_sleep_time} -le 0 ]] && op_sleep_time=30

  setup_curl
  status_code=$(ACURL -X GET "${PROJECT_URL}/operations/${apigee_op_id}")
  if [[ "${status_code}" != "200" ]]; then
    logerr "unable to get apigee operation id '${apigee_op_id}' for project '${PROJECT_ID}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi

  done=$(jq -r .done "${CURL_DATA_FILE}")
  state=$(jq -r .metadata.state "${CURL_DATA_FILE}")
  op_type=$(jq -r .metadata.operationType "${CURL_DATA_FILE}")
  resource=$(jq -r .metadata.targetResourceName "${CURL_DATA_FILE}")
  error_code=$(jq -r .error.code "${CURL_DATA_FILE}")
  if [[ "${done}" != "true" ]]; then
    log "apigee operation '${apigee_op_id}' is in '${state}' state. Resource '${resource}'. Type: '${op_type}'. Sleeping for ${op_sleep_time} seconds."
    sleep "${op_sleep_time}"
    wait_for_operation "${apigee_op_id}" "${op_sleep_time}"
    return $?
  fi
  log "Operation Response: '$(jq -c . "${CURL_DATA_FILE}")'"

  if [[ "${error_code}" != "null" ]]; then
    logerr "apigee operation '${apigee_op_id}' completed with error. Resource '${resource}'. Type: '${op_type}'. Exiting."
    return 1
  fi

  log "apigee operation '${apigee_op_id}' completed successfully. Resource '${resource}'. Type: '${op_type}'."
  return 0
}
