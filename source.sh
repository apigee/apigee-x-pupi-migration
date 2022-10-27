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

PROJECT_ID=""    # Project ID of Apigee Organization.

[[ -z "${PROJECT_ID}" ]] && { echo "PROJECT_ID variable is required in source.sh. Exiting." && exit 1; }
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)") || { echo "unable to fetch PROJECT_NUMBER from PROJECT_ID. Exiting." && exit 1; }
AUTH="Authorization: Bearer $(gcloud auth print-access-token)"
export PROJECT_ID PROJECT_NUMBER AUTH

# This is a template of variable list for each region.
# Copy this block, change the function name to include actual region,
# with ALL CAPS & replace '-' with '_'.
# Eg: For us-east1 region, function name will be "INIT_REGION_US_EAST1".
function INIT_REGION_TBD {
  # Apigee Instance Configurations.
  export INSTANCE_NAME=             # Name of the Apigee Instance.
  export RUNTIME_LOCATION=          # Region of the Apigee Instance.
  export DISK_KEY_PROJECT_ID=       # Project ID where KMS Keys exists. If left empty, this defaults to Apigee Org's PROJECT_ID.
  export DISK_KEY_RING_NAME=        # Name of the KMS Key Ring.
  export DISK_KEY_NAME=             # Name of the KMS Key.
  export IP_RANGE=                  # [CSV] /22 & /28 IP Ranges. [OPTIONAL].
  export CONSUMER_ACCEPT_LIST=      # [CSV] Projects for PSC allow-listing. [OPTIONAL].
  export ENVIRONMENTS_LIST=         # [CSV] Environments to attach to/detach from the Apigee Instance.

  # Northbound Routing Configurations.
  export VPC_NAME=                  # Name of the VPC network peered with Apigee. For shared-vpc, use a full-path.
  export VPC_SUBNET=                # Name of the VPC subnet used to create MIG for Bridge VMs.
  export BACKEND_SERVICE=           # Name of the backend-service load-balancing the MIG/NEG.
  export MIG_NAME=                  # Name of the managed-instance-group hosting the Bridge VMs. [Required only for MIG proxy]
  export NEG_NAME=                  # Name of the PSC network-endpoint-group for apigee service-attachment. [Required only for PSC NEG]
}
