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
# This action is to create / attach / detach / delete the network-endpoint-group (NEG)
# for the Apigee Instance's Service Attachment of the given region to the
# backend-service of the load balancer.
#
# Note: This script neither creates a new backend-service nor a new load balancer.
# Instead, it creates/deletes network-endpoint-group (NEG) to Apigee's
# Service Attachment Endpoint and attaches/detaches the NEG as a backend
# to the existing backend service.
#
# Usage:
#     bash ${0} -r|--region <REGION> [--create|--attach|--detach|--delete]
#         where, 'REGION' is the runtime region of the Apigee Instance.
#                '--create' will only create NEG for the Apigee Instance.
#                '--attach' will create NEG for the Apigee Instance and attach it as backend to XLB's backend service.
#                '--detach' will only remove NEG for the Apigee Instance as backend from XLB's backend service.
#                '--delete' will remove NEG for the Apigee Instance as backend from XLB's backend service and delete it.
#
# Examples:
# To create the NEG backend for 'us-east1' Apigee Instance.
#     bash ${0} -r us-east1 --create
#
# To create & attach the NEG backend of 'us-east1' Apigee Instance to backend service,
#     bash ${0} -r us-east1 --attach
#
# To detach the NEG backend of 'us-east1' Apigee Instance from backend service,
#     bash ${0} -r us-east1 --detach
#
# To detach & delete the NEG backend of 'us-east1' Apigee Instance.
#     bash ${0} -r us-east1 --delete
#**
"""
exit 1
}


# get_apigee_sa sets the 'serviceAttachment' field of Apigee Instance as 'APIGEE_ENDPOINT'.
function get_apigee_sa {
  setup_curl
  status_code=$(ACURL -X GET "${PROJECT_URL}/instances/${INSTANCE_NAME}")
  if [[ "${status_code}" == "404" ]]; then
    logerr "apigee instance do not exists in '${RUNTIME_LOCATION}'. Exiting."
    return 1
  elif [[ "${status_code}" != "200" ]]; then
    logerr "error while fetching apigee instance in '${RUNTIME_LOCATION}'. Exiting."
    return 1
  fi

  log "apigee instance payload: '$(jq -c . "${CURL_DATA_FILE}")'"
  APIGEE_ENDPOINT=$(jq -r .serviceAttachment "${CURL_DATA_FILE}")
  if [[ -z "${APIGEE_ENDPOINT}" ]]; then
    logerr "failed to get apigee endpoint ('serviceAttachment' field) from apigee instance ${INSTANCE_NAME}"
    return 1
  fi

  return 0
}

# create_neg creates network-endpoint-group (NEG) for the Apigee Instance
# in the given region.
function create_neg {
  get_apigee_sa || return 1
  log "creating NEG '${NEG_NAME}' in the region '${RUNTIME_LOCATION}'."

  gcloud compute network-endpoint-groups create "${NEG_NAME}" \
    --project               "${PROJECT_ID}"                   \
    --region                "${RUNTIME_LOCATION}"             \
    --network               "${VPC_NAME}"                     \
    --subnet                "${VPC_SUBNET}"                   \
    --psc-target-service    "${APIGEE_ENDPOINT}"              \
    --network-endpoint-type "private-service-connect"         \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "create network-endpoint-group response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    resource="projects/${PROJECT_ID}/regions/${RUNTIME_LOCATION}/networkEndpointGroups/${NEG_NAME}"
    if ! grep -qF "The resource '${resource}' already exists" "${CURL_DATA_FILE}"; then
      logerr "failed to create network-endpoint-group '${NEG_NAME}' in region '${RUNTIME_LOCATION}'. Exiting."
      return 1
    fi
    log "network-endpoint-group '${NEG_NAME}' already exists in project '${PROJECT_ID}'."
  fi

  return 0
}

# delete_neg deletes network-endpoint-group (NEG) for the Apigee Instance
# in the given region.
function delete_neg {
  get_apigee_sa || return 1
  log "deleting NEG '${NEG_NAME}' in the region '${RUNTIME_LOCATION}'."

  gcloud compute network-endpoint-groups delete "${NEG_NAME}" \
    --project               "${PROJECT_ID}"                   \
    --region                "${RUNTIME_LOCATION}"             \
     -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "delete network-endpoint-group response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    resource="projects/${PROJECT_ID}/regions/${RUNTIME_LOCATION}/networkEndpointGroups/${NEG_NAME}"
    if ! grep -qF "The resource '${resource}' was not found" "${CURL_DATA_FILE}"; then
      logerr "failed to delete network-endpoint-group '${NEG_NAME}' in region '${RUNTIME_LOCATION}'. Exiting."
      return 1
    fi
    log "network-endpoint-group '${NEG_NAME}'has been already deleted."
  fi
}

# add_neg_backend adds the network-endpoint-group to the backend service
# of the load balancer.
function add_neg_backend {
  log "adding NEG backend '${NEG_NAME}' to backend service '${BACKEND_SERVICE}'."
  gcloud compute backend-services add-backend "${BACKEND_SERVICE}" \
    --project "${PROJECT_ID}"       \
    --network-endpoint-group "${NEG_NAME}" \
    --network-endpoint-group-region "${RUNTIME_LOCATION}" \
    --global \
     -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "add backend response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    if grep -qF "Duplicate network endpoint groups in backend service" "${CURL_DATA_FILE}"; then
      log "backend '${NEG_NAME}' has been already attached to backend service '${BACKEND_SERVICE}'."
      return 0
    fi
    logerr "failed to add backend '${NEG_NAME}' to backend service '${BACKEND_SERVICE}'. Exiting."
    return 1
  fi

  return 0
}

# remove_neg_backend removes the network-endpoint-group from the backend service
# of the load balancer.
function remove_neg_backend {
  log "removing NEG backend '${NEG_NAME}' from backend service '${BACKEND_SERVICE}'."
  gcloud compute backend-services remove-backend "${BACKEND_SERVICE}" \
    --project "${PROJECT_ID}"                                         \
    --network-endpoint-group "${NEG_NAME}" \
    --network-endpoint-group-region "${RUNTIME_LOCATION}" \
    --global \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "remove backend response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    message="Backend [${NEG_NAME}] in region [${RUNTIME_LOCATION}] is not a backend of backend service [${BACKEND_SERVICE}]"
    if grep -qF "${message}" "${CURL_DATA_FILE}"; then
      log "backend '${NEG_NAME}' has been already removed from backend service '${BACKEND_SERVICE}'."
      return 0
    fi
    logerr "failed to remove backend '${NEG_NAME}' from backend service '${BACKEND_SERVICE}'. Exiting."
    return 1
  fi

  return 0
}

# enable_connection_draining enables connection draining of the
# backend service on the load balancer
function enable_connection_draining {
  log "enabling connection draining of ${connection_draining_timeout} seconds on backend service '${BACKEND_SERVICE}'."

  # update backend-service to enable connection draining is idempotent by default.
  gcloud compute backend-services update "${BACKEND_SERVICE}"       \
    --project "${PROJECT_ID}"                                       \
    --connection-draining-timeout="${connection_draining_timeout}"  \
    --global                                                        \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "connection draining response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
   logerr "failed to enable connection draining on backend service '${BACKEND_SERVICE}'. Exiting."
   return 1
  fi

  return 0
}

#################### ~ MAIN STARTS HERE ~ ####################

# Process input parameters.
[[ $# -eq 0 ]] && usage
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -r|--region)    REGION=$2; shift ;;
    --create)       CREATE=1;        ;;
    --attach)       ATTACH=1;        ;;
    --detach)       DETACH=1;        ;;
    --delete)       DELETE=1;        ;;
    *)              usage            ;;
  esac
  shift
done

if [[ "$((CREATE + ATTACH + DETACH + DELETE))" != 1 ]]; then
  logerr "incorrect flag. provide one of '--create' or '--attach' or '--delete' or '--detach'."
  usage
fi

init_region "${REGION}" || exit 1

# Global variables.
connection_draining_timeout=60

# Create NEG Backend for proxying Apigee Instance through XLB.
if [[ "${CREATE}" -eq 1 ]]; then
  create_neg || exit 1
  log "successfully created NEG backend '${NEG_NAME}' for apigee instance in region '${RUNTIME_LOCATION}'. Ready to attach to the backend-service of the load balancer."
  exit 0
fi

# Attach NEG Backend of Apigee Instance to XLB.
if [[ "${ATTACH}" -eq 1 ]]; then
  create_neg      || exit 1
  add_neg_backend || exit 1
  log "successfully created NEG backend '${NEG_NAME}' for apigee instance in region '${RUNTIME_LOCATION}' and attached it to backend-service '${BACKEND_SERVICE}' of the load balancer."
  exit 0
fi

# Detach the NEG backend of Apigee Instance from XLB.
if [[ "${DETACH}" -eq 1 ]]; then
  prompt "Do you want to continue with detaching NEG backend for apigee instance in region '${REGION}'" \
    || { logerr "Cancelling request. Exiting." && exit 1; }
  enable_connection_draining || exit 1
  remove_neg_backend         || exit 1
  log "successfully detached NEG backend '${NEG_NAME}' for apigee instance in region '${RUNTIME_LOCATION}' from backend-service '${BACKEND_SERVICE}' of the load balancer."
  exit 0
fi

# Delete NEG backend of Apigee Instance.
if [[ "${DELETE}" -eq 1 ]]; then
  prompt "Do you want to continue with detaching & delete NEG backend for apigee instance in region '${REGION}'" \
    || { logerr "Cancelling request. Exiting." && exit 1; }
  enable_connection_draining || exit 1
  remove_neg_backend         || exit 1
  delete_neg                 || exit 1
  log "successfully detached NEG backend '${NEG_NAME}' for apigee instance in region '${RUNTIME_LOCATION}' from backend-service '${BACKEND_SERVICE}' of the load balancer, and deleted it."
  exit 0
fi