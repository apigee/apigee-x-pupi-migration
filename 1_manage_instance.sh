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
# This action is to manage creation / deletion of Apigee Instance for the given region.
#
# Usage:
#     bash ${0} -r|--region <REGION> --create|--delete
#         where, 'REGION' is the runtime region of the Apigee Instance to be created.
#                '--create' will provision an Apigee instance in the given region.
#                '--delete' will delete the Apigee instance in the given region.
#
# Examples:
# To provision 'us-east1' Apigee Instance,
#     bash ${0} -r us-east1 --create
#
# To delete 'us-east1' Apigee Instance,
#     bash ${0} -r us-east1 --delete
#**
"""
exit 1
}

# provision_kms creates KMS Ring & KMS Key required for Apigee Instance, and
# grants access for the Apigee Service Agent to use the KMS Key.
function provision_kms {
  # Check and create KMS Key Ring.
  keyring=$(gcloud kms keyrings describe "${DISK_KEY_RING_NAME}" \
    --location "${RUNTIME_LOCATION}" \
    --project "${PROJECT_ID}"        \
    --format json 2>/dev/null | jq -r .name)
  if [[ "${keyring}" == "${kms_keyring_fmt}" ]]; then
    log "kms keyring '${kms_keyring_fmt}' is already present. Continuing."
  else
    response=$(gcloud kms keyrings create "${DISK_KEY_RING_NAME}" \
      --location "${RUNTIME_LOCATION}" \
      --project "${PROJECT_ID}" 2>&1)
    [[ $? -ne 0 ]] && logerr "failed to create kms keyring '${kms_keyring_fmt}'. err: '${response}'" && return 1
    log "successfully created kms keyring '${kms_keyring_fmt}'"
  fi

  # Check and create KMS Key.
  key=$(gcloud kms keys describe "${DISK_KEY_NAME}" \
    --keyring "${DISK_KEY_RING_NAME}" \
    --location "${RUNTIME_LOCATION}"  \
    --project "${PROJECT_ID}"         \
    --format json 2>/dev/null | jq -r .name)
  if [[ "${key}" == "${kms_key_fmt}" ]]; then
    log "kms key '${kms_key_fmt}' is already present. Continuing."
  else
    response=$(gcloud kms keys create "${DISK_KEY_NAME}" --purpose "encryption" \
      --keyring "${DISK_KEY_RING_NAME}" \
      --location "${RUNTIME_LOCATION}"  \
      --project "${PROJECT_ID}" 2>&1)
    [[ $? -ne 0 ]] && logerr "failed to create kms key '${kms_key_fmt}'. err: '${response}'" && return 1
    log "successfully created kms key '${kms_key_fmt}'"
  fi

  apigee_agent="service-${PROJECT_NUMBER}@gcp-sa-apigee.iam.gserviceaccount.com"
  response=$(gcloud kms keys add-iam-policy-binding "${DISK_KEY_NAME}" \
    --location "${RUNTIME_LOCATION}"  \
    --keyring "${DISK_KEY_RING_NAME}" \
    --member "serviceAccount:${apigee_agent}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project "${PROJECT_ID}" 2>&1)

  [[ $? -ne 0 ]] && logerr "failed to grant access for the Apigee Service Agent '${apigee_agent}' to use the kms key: '${kms_key_fmt}'. err: '${response}'" && return 1
  log "successfully granted Apigee Service Agent '${apigee_agent}' to use kms key."
  return 0
}

# check_for_instance verifies the existence of Apigee instances, and
# returns custom error code based on their status.
# 0 - Instance not found (404).
# 2 - Instance Exists, in "ACTIVE" state.
# 3 - Instance Exists, in "CREATING" state.
# 4 - Instance Exists, in "DELETING" state.
# 5 - Instance Exists, in "UPDATING" state.
# 1 - All other errors.
function check_for_instance {
  setup_curl
  status_code=$(ACURL -X GET "${PROJECT_URL}/instances/${INSTANCE_NAME}")
  if [[ "${status_code}" == "404" ]]; then
    return 0
  elif [[ "${status_code}" == "200" ]]; then
    log "apigee instance payload: '$(jq -c . "${CURL_DATA_FILE}")'"
    state=$(jq -r .state "${CURL_DATA_FILE}")
    case "${state}" in
      "ACTIVE")   return 2  ;;
      "CREATING") return 3  ;;
      "DELETING") return 4  ;;
      "UPDATING") return 5  ;;
      *)
        logerr "apigee instance '${INSTANCE_NAME}' exists in '${PROJECT_ID}' and is in unknown state - '${state}'. Wait for the operation to complete."
        return 1
        ;;
      esac
  fi

  # Return error when it is not 404 or 200.
  logerr "error while fetching instance '${INSTANCE_NAME}' in project '${PROJECT_ID}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
  return 1
}

# create_instance creates apigee instance in the given region.
# It returns error when the instance already exists.
function create_instance {
  check_for_instance ; rc=$?
  case "${rc}" in
    "0")
      log "apigee instance '${INSTANCE_NAME}' does not exist in '${PROJECT_ID}'. Proceeding with the creation."
      ;;
    "2")
      logerr "apigee instance '${INSTANCE_NAME}' already exists in '${PROJECT_ID}' and is in 'ACTIVE' state. Exiting."
      return 1
      ;;
    "3"|"4"|"5")
      logerr "apigee instance '${INSTANCE_NAME}' already exists in '${PROJECT_ID}' and is in '${state}' state. Wait for the operation to complete and retry."
      return 1
      ;;
    *)
      return 1
      ;;
  esac

  provision_kms || return 1

  ca_list="[]"
  [[ -n "${CONSUMER_ACCEPT_LIST}" ]] && ca_list=$(echo "${CONSUMER_ACCEPT_LIST}" | tr -d " " | sed 's/,/","/g' | sed 's/^/[\"/g' | sed 's/$/\"]/g' | jq -c .)
  payload='{
    "name":"'"${INSTANCE_NAME}"'",
    "location":"'"${RUNTIME_LOCATION}"'",
    "diskEncryptionKeyName":"'"${kms_key_fmt}"'",
    "ipRange":"'"${IP_RANGE}"'",
    "consumerAcceptList":'"${ca_list}"'
  }'
  log "payload for creating apigee instance: '$(echo "${payload}" | jq -c .)'"

  setup_curl
  status_code=$(ACURL -X POST "${PROJECT_URL}/instances" \
    -H "Content-Type:application/json" \
    -d "${payload}")
  if [[ "${status_code}" != "200" ]]; then
    logerr "failed to create the apigee instance '${INSTANCE_NAME}' in project '${PROJECT_ID}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi

  log "successfully scheduled apigee instance creation job for '${INSTANCE_NAME}' in project '${PROJECT_ID}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'"
  instance_op_id=$(jq -r .name "${CURL_DATA_FILE}" | rev | cut -d '/' -f1 | rev)
  wait_for_operation "${instance_op_id}" "${op_sleep_time}" || return 1

  return 0
}

# delete_instance deletes apigee instance in the given region.
# It returns error when the instance does not exist or exists
# in other states than 'ACTIVE' like 'DELETING, CREATING, UPDATING', etc.
function delete_instance {
  check_for_instance ; rc=$?
  case "${rc}" in
    "0")
      logerr "apigee instance '${INSTANCE_NAME}' does not exist in '${PROJECT_ID}'. Exiting."
      return 1
      ;;
    "2")
      log "apigee instance '${INSTANCE_NAME}' exist in '${PROJECT_ID}'. Proceeding with the deletion."
      ;;
    "3"|"4"|"5")
      logerr "apigee instance '${INSTANCE_NAME}' exists in '${PROJECT_ID}' and is in '${state}' state. Wait for the operation to complete and retry."
      return 1
      ;;
    *)
      return 1
      ;;
  esac

  setup_curl
  status_code=$(ACURL -X DELETE "${PROJECT_URL}/instances/${INSTANCE_NAME}")
  if [[ "${status_code}" == "404" ]]; then
    logerr "apigee instance '${INSTANCE_NAME}' does not exist in '${PROJECT_ID}'. Exiting."
    return 1
  elif [[ "${status_code}" != "200" ]]; then
    logerr "failed to delete the apigee instance '${INSTANCE_NAME}' in project '${PROJECT_ID}'. Code: '${status_code}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'. Exiting."
    return 1
  fi

  log "successfully scheduled apigee instance deletion job for '${INSTANCE_NAME}' in project '${PROJECT_ID}'. Response: '$(jq -c . "${CURL_DATA_FILE}")'"
  instance_op_id=$(jq -r .name "${CURL_DATA_FILE}" | rev | cut -d '/' -f1 | rev)
  wait_for_operation "${instance_op_id}" "${op_sleep_time}" || return 1

  return 0
}

#################### ~ MAIN STARTS HERE ~ ####################

# Process input parameters.
[[ $# -eq 0 ]] && usage
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -r|--region)    REGION=$2; shift ;;
    --create)       CREATE=true      ;;
    --delete)       DELETE=true      ;;
    *)              usage            ;;
  esac
  shift
done

if [[ "${CREATE}" == "${DELETE}" ]]; then
  logerr "incorrect flag. provide either '--create' or '--delete'."
  usage
fi

init_region "${REGION}" || exit 1

# Global variables.
op_sleep_time=60 # Wait time in seconds before rechecking operation status.
instance_op_id=""
kms_keyring_fmt="projects/${PROJECT_ID}/locations/${RUNTIME_LOCATION}/keyRings/${DISK_KEY_RING_NAME}"
kms_key_fmt="${kms_keyring_fmt}/cryptoKeys/${DISK_KEY_NAME}"
target_resource="organizations/${PROJECT_ID}/instances/${INSTANCE_NAME}"

# Delete Apigee Instance flow.
if [[ "${DELETE}" == true ]]; then
  prompt "Do you want to continue with deleting apigee instance in region '${REGION}'" \
    || { logerr "Cancelling request. Exiting." && exit 1; }
  delete_instance       || exit 1
  log "successfully deleted apigee instance '${target_resource}' in region '${RUNTIME_LOCATION}'."
  exit 0
fi

# Create Apigee Instance flow.
create_instance         || exit 1
log "successfully created apigee instance '${target_resource}' in region '${RUNTIME_LOCATION}'."
