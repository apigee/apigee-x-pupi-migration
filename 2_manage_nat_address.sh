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
# This action is to reserve & activate, or release southbound NAT Addresses to
# Apigee Instance for the given region. Customer should add the NAT IPs from
# the output of this script to their target allow-listing while reserving them.
#
# Usage:
#     bash ${0} -r|--region <REGION> [-c|--count <COUNT>] --reserve|--release|--list
#         where, 'REGION' is the runtime region of the Apigee Instance.
#                'COUNT'  is the number of southbound NAT addresses to assign for Apigee Instance.
#                         It is optional and defaults to 2.
#                '--reserve' will reserve & activate the NAT addresses to the Apigee Instance.
#                '--release' will release all the NAT addresses associated to the Apigee Instance.
#                '--list' will list all the active NAT addresses associated to the Apigee Instance.
#
# Examples:
# To reserve & activate 3 NAT addresses to 'us-east1' Apigee Instance,
#     bash ${0} -r us-east1 -c 3 --reserve
#
# To release ALL the NAT addresses of 'us-east1' Apigee Instance,
#     bash ${0} -r us-east1 --release
#
# To list ALL the NAT addresses of 'us-east1' Apigee Instance,
#     bash ${0} -r us-east1 --list
#**
"""
exit 1
}

# reserve_nat_address reserves NAT address for the given region.
function reserve_nat_address {
  nat_id="${nat_id_prefix}-${1}"
  payload='{
    "name":"'"${nat_id}"'"
  }'
  log "payload for reserving NAT address for apigee instance '${INSTANCE_NAME}' in region '${RUNTIME_LOCATION}': '$(echo "${payload}" | jq -c .)'"

  setup_curl
  status_code=$(ACURL -X POST "${PROJECT_URL}/instances/${INSTANCE_NAME}/natAddresses" \
    -H "Content-Type:application/json" \
    -d "${payload}")
  if [[ "${status_code}" == "409" ]]; then
    log "NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}' already exists."
    return 0
  elif [[ "${status_code}" != "200" ]]; then
    logerr "failed to reserve NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi

  log "successfully scheduled NAT address reservation job for apigee instance '${INSTANCE_NAME}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'"
  nat_op_id=$(jq -r .name "${CURL_DATA_FILE}" | rev | cut -d '/' -f1 | rev)
  wait_for_operation "${nat_op_id}" "${op_sleep_time}"
  return $?
}

# activate_nat_address activates NAT addresses that were reserved for the given region.
function activate_nat_address {
  nat_id="${nat_id_prefix}-${1}"
  setup_curl
  status_code=$(ACURL -X POST "${PROJECT_URL}/instances/${INSTANCE_NAME}/natAddresses/${nat_id}:activate" \
    -H "Content-Type:application/json" \
    -d "{}")
  if [[ "${status_code}" != "200" ]]; then
    logerr "failed to activate NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi

  log "successfully scheduled NAT address '${nat_id}' activation job for '${INSTANCE_NAME}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'"
  nat_op_id=$(jq -r .name "${CURL_DATA_FILE}" | rev | cut -d '/' -f1 | rev)
  wait_for_operation "${nat_op_id}" "${op_sleep_time}"
  if [[ $? -ne 0 ]]; then
    logerr "activation failed for NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}'. Exiting."
  fi

  log "successfully activated NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}'."
  return 0
}

# get_nat_address returns the details of given NAT address.
function get_nat_address {
  nat_id="${nat_id_prefix}-${1}"
  setup_curl
  status_code=$(ACURL -X GET "${PROJECT_URL}/instances/${INSTANCE_NAME}/natAddresses/${nat_id}")
  if [[ "${status_code}" != "200" ]]; then
    logerr "failed to get NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi

  nat_ip_addresses+=("$(jq -r ".ipAddress" "${CURL_DATA_FILE}")")
  log "NAT address [${1}]: '$(jq -c . "${CURL_DATA_FILE}")'"
  return 0
}

# list_active_nat_addresses lists the details of all the active NAT addresses.
function list_active_nat_addresses {
  status_code=$(ACURL -X GET "${PROJECT_URL}/instances/${INSTANCE_NAME}/natAddresses")
  if [[ "${status_code}" != "200" ]]; then
    logerr "failed to list NAT address for apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi
  log "list NAT addresses: '$(jq -c . "${CURL_DATA_FILE}")'"

  nat_ids=$(jq -r '.natAddresses[] | select(.state=="ACTIVE") | .name' "${CURL_DATA_FILE}" 2>/dev/null)
  IFS=' ' read -r -a nat_ip_addresses <<< "$(jq -r '.natAddresses[] | select(.state=="ACTIVE") | .ipAddress' "${CURL_DATA_FILE}" 2>/dev/null | xargs)"
  if [[ -z "${nat_ids}" ]] || [[ "${#nat_ip_addresses[@]}" -eq 0 ]]; then
    log "no active NAT addresses are found for apigee instance '${INSTANCE_NAME}'"
    return 0
  fi

  log "active NAT addresses: [$(echo "${nat_ip_addresses[*]}" | tr ' ' ',')]"
  return 0
}

# release_nat_address releases all the NAT addresses for the given region.
function release_nat_address {
  setup_curl
  status_code=$(ACURL -X GET "${PROJECT_URL}/instances/${INSTANCE_NAME}/natAddresses")
  if [[ "${status_code}" != "200" ]]; then
    logerr "failed to list NAT address for apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi

  nat_ids=$(jq -r .natAddresses[].name "${CURL_DATA_FILE}" 2>/dev/null)
  if [[ -z "${nat_ids}" ]]; then
    log "no NAT addresses are found for apigee instance '${INSTANCE_NAME}' to release."
    return 0
  fi

  for nat_id in ${nat_ids}
  do
    log "releasing NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}' in region '${RUNTIME_LOCATION}'."

    setup_curl
    status_code=$(ACURL -X DELETE "${PROJECT_URL}/instances/${INSTANCE_NAME}/natAddresses/${nat_id}")
    if [[ "${status_code}" == "404" ]]; then
      log "NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}' does not exist."
      continue
    elif [[ "${status_code}" != "200" ]]; then
      logerr "failed to release NAT address '${nat_id}' for apigee instance '${INSTANCE_NAME}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
      return 1
    fi

    log "successfully scheduled NAT address release job for apigee instance '${INSTANCE_NAME}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'"
    nat_op_id=$(jq -r .name "${CURL_DATA_FILE}" | rev | cut -d '/' -f1 | rev)
    wait_for_operation "${nat_op_id}" "${op_sleep_time}" || return 1
  done

  log "successfully released all the NAT addresses for apigee instance '${INSTANCE_NAME}'."
  log "ensure to remove these NAT addresses from your target allow-listing [$(echo "${nat_ip_addresses[*]}" | tr ' ' ',')]."
  return 0
}

#################### ~ MAIN STARTS HERE ~ ####################

# Process input parameters.
[[ $# -eq 0 ]] && usage
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -r|--region)    REGION=$2;    shift  ;;
    -c|--count)     COUNT=$2;     shift  ;;
    --reserve)      RESERVE=true;        ;;
    --release)      RELEASE=true;        ;;
    --list)         LIST=true;           ;;
    *)              usage                ;;
  esac
  shift
done

if [[ ${COUNT} -le 0 ]]; then
  COUNT=2
fi
if [[ "${RESERVE}" == "${RELEASE}" ]] && [[ -z "${LIST}" ]]; then
  logerr "incorrect flag. provide either '--reserve' or '--release'."
  usage
fi

init_region "${REGION}" || exit 1

# Global variables.
op_sleep_time=10 # Wait time in seconds before rechecking operation status.
nat_op_id=""
nat_id_prefix="nat-ip-${RUNTIME_LOCATION}"
declare -a nat_ip_addresses=()

# Release NAT address flow.
if [[ "${RELEASE}" == true ]]; then
  list_active_nat_addresses || exit 1
  prompt "Do you want to continue with releasing NAT addresses in region '${REGION}'" \
    || { logerr "Cancelling request. Exiting." && exit 1; }
  release_nat_address || exit 1
  exit 0
fi

# Reserve & Activate NAT address flow.
if [[ "${RESERVE}" == true ]]; then
  for (( i=0; i<COUNT; i++ ))
  do
    reserve_nat_address "${i}" || exit 1
    activate_nat_address "${i}" || exit 1
  done

  for (( i=0; i<COUNT; i++ ))
  do
    get_nat_address "${i}" || exit 1
  done

  log "add these '$COUNT' NAT addresses in your target allow-listing [$(echo "${nat_ip_addresses[*]}" | tr ' ' ',')]."
  exit 0
fi

# List NAT addresses flow.
if [[ "${LIST}" == true ]]; then
  list_active_nat_addresses || exit 1
  exit 0
fi
