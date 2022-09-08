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
# This action is to create / attach / detach / delete the managed-instance-group (MIG)
# for the Apigee Instance of the given region to the backend-service of the load balancer.
#
# Note: This script neither creates a new backend-service nor a new load balancer.
# Instead, it creates/deletes managed-instance-group (MIG) that proxies traffic
# to Apigee Endpoint, and attaches/detaches the MIG as a backend to the existing
# backend service.
#
# Usage:
#     bash ${0} -r|--region <REGION> [--create|--attach|--detach|--delete]
#         where, 'REGION' is the runtime region of the Apigee Instance.
#                '--create' will only create MIG for the Apigee Instance.
#                '--attach' will create MIG for the Apigee Instance and attach it as backend to XLB's backend service.
#                '--detach' will only remove MIG for the Apigee Instance as backend from XLB's backend service.
#                '--delete' will remove MIG for the Apigee Instance as backend from XLB's backend service and delete it.
#
# Examples:
# To create the MIG backend for 'us-east1' Apigee Instance.
#     bash ${0} -r us-east1 --create
#
# To create & attach the MIG backend of 'us-east1' Apigee Instance to backend service,
#     bash ${0} -r us-east1 --attach
#
# To detach the MIG backend of 'us-east1' Apigee Instance from backend service,
#     bash ${0} -r us-east1 --detach
#
# To detach & delete the MIG backend of 'us-east1' Apigee Instance.
#     bash ${0} -r us-east1 --delete
#**
"""
exit 1
}

# get_apigee_host sets the 'host' field of Apigee Instance as 'APIGEE_ENDPOINT.
function get_apigee_host {
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
  APIGEE_ENDPOINT=$(jq -r .host "${CURL_DATA_FILE}")
  if [[ -z "${APIGEE_ENDPOINT}" ]]; then
    logerr "failed to get apigee endpoint ('host' field) from apigee instance ${INSTANCE_NAME}"
    return 1
  fi

  return 0
}

# create_mig creates instance-template and managed-instance-group (MIG)
# for the Apigee Instance in the given region.
# It also sets the autoscaling & the named ports for the MIG.
function create_mig {
  get_apigee_host || return 1
  log "creating instance-template & managed-instance-group '${MIG_NAME}' in the region '${RUNTIME_LOCATION}'."
  gcloud compute instance-templates create "${MIG_NAME}" \
    --project         "${PROJECT_ID}"       \
    --region          "${RUNTIME_LOCATION}" \
    --network         "${VPC_NAME}"         \
    --subnet          "${VPC_SUBNET}"       \
    --machine-type    e2-medium             \
    --image-family    debian-10             \
    --image-project   debian-cloud          \
    --boot-disk-size  20GB                  \
    --tags=https-server,apigee-mig-proxy,gke-apigee-proxy \
    --metadata ENDPOINT="${APIGEE_ENDPOINT}",startup-script-url=gs://apigee-5g-saas/apigee-envoy-proxy-release/latest/conf/startup-script.sh \
    -q > "${CURL_DATA_FILE}" 2>&1 
  rv=$?; log "create instance-template response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    resource="projects/${PROJECT_ID}/global/instanceTemplates/${MIG_NAME}"
    if ! grep -qF "The resource '${resource}' already exists" "${CURL_DATA_FILE}"; then
      logerr "failed to create instance-template '${MIG_NAME}' in region '${RUNTIME_LOCATION}'. Exiting."
      return 1
    fi
    log "instance-template '${MIG_NAME}' already exists in project '${PROJECT_ID}'."
  fi

  gcloud compute instance-groups managed create "${MIG_NAME}" \
    --project         "${PROJECT_ID}"       \
    --region          "${RUNTIME_LOCATION}" \
    --template        "${MIG_NAME}"         \
    --base-instance-name "apigee-mig"       \
    --size 2                                \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "create instance-group response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    resource="projects/${PROJECT_ID}/regions/${RUNTIME_LOCATION}/instanceGroupManagers/${MIG_NAME}"
    if ! grep -qF "The resource '${resource}' already exists" "${CURL_DATA_FILE}"; then
      logerr "failed to create managed-instance-group '${MIG_NAME}' in region '${RUNTIME_LOCATION}'. Exiting."
      return 1
    fi
    log "managed-instance-group '${MIG_NAME}' already exists in project '${PROJECT_ID}'."
  fi

  # set-autoscaling is idempotent by default.
  gcloud compute instance-groups managed set-autoscaling "${MIG_NAME}" \
    --project         "${PROJECT_ID}"       \
    --region          "${RUNTIME_LOCATION}" \
    --max-num-replicas 3                    \
    --target-cpu-utilization 0.75           \
    --cool-down-period 90                   \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "set autoscaling to instance-group response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    logerr "failed to set autoscaling to managed-instance-group '${MIG_NAME}' in region '${RUNTIME_LOCATION}'. Exiting."
    return 1
  fi

  # set-named-ports is idempotent by default.
  gcloud compute instance-groups managed set-named-ports "${MIG_NAME}" \
    --project      "${PROJECT_ID}"          \
    --region       "${RUNTIME_LOCATION}"    \
    --named-ports  "https:443"              \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "set name ports to instance-group response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    logerr "failed to set named port for managed-instance-group '${MIG_NAME}' in region '${RUNTIME_LOCATION}'. Exiting."
    return 1
  fi

  return 0
}

# delete_mig deletes the managed-instance-group (MIG) & instance-template
# for the Apigee Instance in the given region.
function delete_mig {
  log "deleting managed-instance-group & instance-template '${MIG_NAME}' in the region '${RUNTIME_LOCATION}'."
  gcloud compute instance-groups managed delete "${MIG_NAME}" \
    --project "${PROJECT_ID}"               \
    --region  "${RUNTIME_LOCATION}"         \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "delete instance-group response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    resource="projects/${PROJECT_ID}/regions/${RUNTIME_LOCATION}/instanceGroupManagers/${MIG_NAME}"
    if ! grep -qF "The resource '${resource}' was not found" "${CURL_DATA_FILE}"; then
      logerr "failed to delete managed-instance-group '${MIG_NAME}' in region '${RUNTIME_LOCATION}'. Exiting."
      return 1
    fi
    log "managed-instance-group '${MIG_NAME}' has been already deleted."
  fi

  gcloud compute instance-templates delete "${MIG_NAME}" \
    --project "${PROJECT_ID}"               \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "delete instance-template response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    resource="projects/${PROJECT_ID}/global/instanceTemplates/${MIG_NAME}"
    if ! grep -qF "The resource '${resource}' was not found" "${CURL_DATA_FILE}"; then
      logerr "failed to delete instance-template '${MIG_NAME}' in region '${RUNTIME_LOCATION}'. Exiting."
      return 1
    fi
    log "instance-template '${MIG_NAME}' has been already deleted."
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

# add_mig_backend adds the managed-instance-group to the backend service
# of the load balancer.
function add_mig_backend {
  log "adding backend '${MIG_NAME}' to backend service '${BACKEND_SERVICE}'."
  gcloud compute backend-services add-backend "${BACKEND_SERVICE}"  \
    --project "${PROJECT_ID}"                                       \
    --instance-group "${MIG_NAME}"                                  \
    --instance-group-region "${RUNTIME_LOCATION}"                   \
    --balancing-mode UTILIZATION                                    \
    --max-utilization 0.8                                           \
    --global                                                        \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "add backend response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    if grep -qF "Duplicate instance groups in backend service" "${CURL_DATA_FILE}"; then
      log "backend '${MIG_NAME}' has been already attached to backend service '${BACKEND_SERVICE}'."
      return 0
    fi
    logerr "failed to add backend '${MIG_NAME}' to backend service '${BACKEND_SERVICE}'. Exiting."
    return 1
  fi

  return 0
}

# remove_mig_backend removes the managed-instance-group from the backend service
# of the load balancer.
function remove_mig_backend {
  log "removing backend '${MIG_NAME}' from backend service '${BACKEND_SERVICE}'."
  gcloud compute backend-services remove-backend "${BACKEND_SERVICE}" \
    --project "${PROJECT_ID}"                                         \
    --instance-group "${MIG_NAME}"                                    \
    --instance-group-region "${RUNTIME_LOCATION}"                     \
    --global                                                          \
    -q > "${CURL_DATA_FILE}" 2>&1
  rv=$?; log "remove backend response: '$(cat "${CURL_DATA_FILE}")'"
  if [[ "${rv}" -ne 0 ]]; then
    message="Backend [${MIG_NAME}] in region [${RUNTIME_LOCATION}] is not a backend of backend service [${BACKEND_SERVICE}]"
    if grep -qF "${message}" "${CURL_DATA_FILE}"; then
      log "backend '${MIG_NAME}' has been already removed from backend service '${BACKEND_SERVICE}'."
      return 0
    fi
    logerr "failed to remove backend '${MIG_NAME}' from backend service '${BACKEND_SERVICE}'. Exiting."
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

# Create MIG Backend for proxying Apigee Instance through XLB.
if [[ "${CREATE}" -eq 1 ]]; then
  create_mig || exit 1
  log "successfully created MIG backend '${MIG_NAME}' for apigee instance in region '${RUNTIME_LOCATION}'. Ready to attach to the backend-service of the load balancer."
  exit 0
fi

# Attach MIG Backend of Apigee Instance to XLB.
if [[ "${ATTACH}" -eq 1 ]]; then
  create_mig      || exit 1
  add_mig_backend || exit 1
  log "successfully created MIG backend '${MIG_NAME}' for apigee instance in region '${RUNTIME_LOCATION}' and attached it to backend-service '${BACKEND_SERVICE}' of the load balancer."
  exit 0
fi

# Detach the MIG backend of Apigee Instance from XLB.
if [[ "${DETACH}" -eq 1 ]]; then
  prompt "Do you want to continue with detaching MIG backend for apigee instance in region '${REGION}'" \
    || { logerr "Cancelling request. Exiting." && exit 1; }
  enable_connection_draining || exit 1
  remove_mig_backend         || exit 1
  log "successfully detached MIG backend '${MIG_NAME}' for apigee instance in region '${RUNTIME_LOCATION}' from backend-service '${BACKEND_SERVICE}' of the load balancer."
  exit 0
fi

# Delete MIG backend of Apigee Instance.
if [[ "${DELETE}" -eq 1 ]]; then
  prompt "Do you want to continue with detaching & delete MIG backend for apigee instance in region '${REGION}'" \
    || { logerr "Cancelling request. Exiting." && exit 1; }
  enable_connection_draining || exit 1
  remove_mig_backend         || exit 1
  delete_mig                 || exit 1
  log "successfully detached MIG backend '${MIG_NAME}' for apigee instance in region '${RUNTIME_LOCATION}' from backend-service '${BACKEND_SERVICE}' of the load balancer, and deleted it."
  exit 0
fi


