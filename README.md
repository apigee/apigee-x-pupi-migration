# Apigee-X Instance Recreation with Zero Downtime

The goal of this playbook is to provide a clear set of tasks/steps to follow to 
successfully recreate Apigee Instances without any downtime or any data-loss. 

--------------------------------------------------------------------------------

## Execution Flow

### Update `source.sh`

Ensure all the variables are provided at `source.sh`. For each region, create a
function `INIT_REGION_${REGION_ID}` containing the variables for the
corresponding region, where `${REGION_ID}` is the name of the region with ALL
CAPS & replace `-` (hyphen) with `_` (underscore). \
**Example:** For `us-east1` region, function name will be
`INIT_REGION_US_EAST1`.

-   `PROJECT_ID`: Project ID of Apigee Organization.
-   `INSTANCE_NAME`: Name of the Apigee Instance to create / delete.
-   `RUNTIME_LOCATION`: Actual GCP region of the Apigee Instance.
-   `DISK_KEY_RING_NAME`: Name of the KMS Key Ring used for disk encryption. If
    it doesn't already exist, it will be created automatically. It will be
    reused if it already exists.
-   `DISK_KEY_NAME`: Name of the KMS Key used for disk encryption. If it doesn't
    already exist, it will be created automatically. It will be reused if it
    already exists.
-   `IP_RANGE`: ***[OPTIONAL]*** Comma separated values of /22 & /28 IP Ranges.
    If provided, make sure the ranges are part of CIDR blocks allocated to the
    service networking. ***Refer
    [Configure service networking](https://cloud.google.com/apigee/docs/api-platform/get-started/configure-service-networking)
    for more details.***
-   `CONSUMER_ACCEPT_LIST`: ***[OPTIONAL]*** Comma separated values of GCP
    Projects for PSC allow-listing.
-   `ENVIRONMENTS_LIST`: Comma separated values of Environments to attach
    to/detach from the Apigee Instance.

**Northbound Routing Configurations:**

-   `VPC_NAME`: Name of the VPC network peered with Apigee. For shared-vpc, use
    a full-path.
-   `VPC_SUBNET`: Name of the VPC subnet used to create managed-instance-group
    for Bridge VMs.
-   `BACKEND_SERVICE`: Name of the backend-service load-balancing the MIG/NEG.
-   `MIG_NAME`: Name of the managed-instance-group hosting the Bridge VMs.
    ***[Required only when using MIG proxy]***
-   `NEG_NAME`: Name of the PSC network-endpoint-group for apigee
    service-attachment. ***[Required only when using PSC NEG]***

### To Provision new Apigee Instance & wire it to route Northbound LB:

Note: While each script periodically checks for the completion of Apigee's
long-running-operations (LRO), you can always monitor their status by running \
**`"bash 5_wait_for_apigee_operation.sh -o ${OPERATION_ID}"`**

#### ► Using Managed-Instance-Group (MIG)

```shell
REGION=<GCP Region to provision new Apigee Instance. Example: "us-east1">
1. bash 1_manage_instance.sh -r ${REGION} --create
2. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --count 2 --reserve
   # If you reserve NAT Addresses, add them to your target allow-listing before proceeding.
3. bash 3_manage_environments.sh -r ${REGION} --attach
4. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --create
5. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --attach
```

#### ► Using Network-Endpoint-Group (NEG)

```shell
REGION=<GCP Region to provision new Apigee Instance. Example: "us-east1">
1. bash 1_manage_instance.sh -r ${REGION} --create
2. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --count 2 --reserve
   # If you reserve NAT Addresses, add them to your target allow-listing before proceeding.
3. bash 3_manage_environments.sh -r ${REGION} --attach
4. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --create
5. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --attach
```

### To remove an existing Apigee Instance:

Note: While each script periodically checks for the completion of Apigee's
long-running-operations (LRO), you can always monitor their status by running \
`"bash 5_wait_for_apigee_operation.sh -o ${OPERATION_ID}"`

#### ► Using Managed-Instance-Group (MIG)

```shell
REGION=<GCP Region of the existing Apigee Instance to de-provision. Example: "us-east1">
1. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --detach
2. bash 3_manage_environments.sh -r ${REGION} --detach
3. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --release
   # If you reserved NAT Addresses, remove them from your target allow-listing.
4. bash 1_manage_instance.sh -r ${REGION} --delete
5. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --delete
```

#### ► Using Network-Endpoint-Group (NEG)

```shell
REGION=<GCP Region of the existing Apigee Instance to de-provision. Example: "us-east1">
1. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --detach
2. bash 3_manage_environments.sh -r ${REGION} --detach
3. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --release
   # If you reserved NAT Addresses, remove them from your target allow-listing.
4. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --delete
5. bash 1_manage_instance.sh -r ${REGION} --delete
```

--------------------------------------------------------------------------------

## Script Details

### 1. Manage Instance: `bash 1_manage_instance.sh -h`

This action is to manage creation / deletion of Apigee Instance for the given
GCP region. While deleting, customer should ensure at least they have one
other region which will be taking traffic to avoid any interruptions/data-loss.

```shell
#**
#
# Usage:
#     bash 1_manage_instance.sh -r|--region <REGION> --create|--delete
#         where, 'REGION' is the runtime region of the Apigee Instance to be created.
#                '--create' will provision an Apigee instance in the given region.
#                '--delete' will delete the Apigee instance in the given region.
#
# Examples:
# To provision 'us-east1' Apigee Instance,
#     bash 1_manage_instance.sh -r us-east1 --create
#
# To delete 'us-east1' Apigee Instance,
#     bash 1_manage_instance.sh -r us-east1 --delete
#**
```

### 2. Manage NAT Address: `bash 2_manage_nat_address.sh -h`

This action is to reserve & activate, or release southbound NAT Addresses to
Apigee Instance for the given region. Customer should add the NAT IPs from
the output of this script to their target allow-listing while reserving them.

```shell
#**
#
# Usage:
#     bash 2_manage_nat_address.sh -r|--region <REGION> [-c|--count <COUNT>] --reserve|--release|--list
#         where, 'REGION' is the runtime region of the Apigee Instance.
#                'COUNT'  is the number of southbound NAT addresses to assign for Apigee Instance.
#                         It is optional and defaults to 2.
#                '--reserve' will reserve & activate the NAT addresses to the Apigee Instance.
#                '--release' will release all the NAT addresses associated to the Apigee Instance.
#                '--list' will list all the active NAT addresses associated to the Apigee Instance.
#
# Examples:
# To reserve & activate 3 NAT addresses to 'us-east1' Apigee Instance,
#     bash 2_manage_nat_address.sh -r us-east1 -c 3 --reserve
#
# To release ALL the NAT addresses of 'us-east1' Apigee Instance,
#     bash 2_manage_nat_address.sh -r us-east1 --release
#
# To list ALL the NAT addresses of 'us-east1' Apigee Instance,
#     bash 2_manage_nat_address.sh -r us-east1 --list
#**
```

### 3. Manage Environments: `bash 3_manage_environments.sh -h`

This action is to attach / detach all the environments to Apigee Instance  for
the given region. The environments should be listed at 'ENVIRONMENTS_LIST'
variable in 'source.sh'.

```shell
#**
#
# Usage:
#     bash 3_manage_environments.sh -r|--region <REGION> [--attach|--detach]
#         where, 'REGION' is the runtime region of the Apigee Instance.
#                '--attach' will attach all the environments to the Apigee Instance in the given region.
#                '--detach' will detach all the environments from the Apigee Instance in the given region.
#
# Examples:
# To attach all Environments to 'us-east1' Apigee Instance,
#     bash 3_manage_environments.sh -r us-east1 --attach
#
# To detach all Environments from 'us-east1' Apigee Instance,
#     bash 3_manage_environments.sh -r us-east1 --detach
#**
```

### 4.1. Manage XLB + MIG Backend: `bash 4_manage_xlb_mig_backend.sh -h`

This action is to create / attach / detach / delete the managed-instance-group
(MIG) for the Apigee Instance of the given region to the backend-service of the
load balancer.

Note: This script neither creates a new backend-service nor a new load balancer.
Instead, it creates/deletes managed-instance-group (MIG) that proxies traffic
to Apigee Endpoint, and attaches/detaches the MIG as a backend to the existing
backend service.

```shell
#**
#
# Usage:
#     bash 4_manage_xlb_mig_backend.sh -r|--region <REGION> [--create|--attach|--detach|--delete]
#         where, 'REGION' is the runtime region of the Apigee Instance.
#                '--create' will only create MIG for the Apigee Instance.
#                '--attach' will create MIG for the Apigee Instance and attach it as backend to XLB's backend service.
#                '--detach' will only remove MIG for the Apigee Instance as backend from XLB's backend service.
#                '--delete' will remove MIG for the Apigee Instance as backend from XLB's backend service and delete it.
#
# Examples:
# To create the MIG backend for 'us-east1' Apigee Instance.
#     bash 4_manage_xlb_mig_backend.sh -r us-east1 --create
#
# To create & attach the MIG backend of 'us-east1' Apigee Instance to backend service,
#     bash 4_manage_xlb_mig_backend.sh -r us-east1 --attach
#
# To detach the MIG backend of 'us-east1' Apigee Instance from backend service,
#     bash 4_manage_xlb_mig_backend.sh -r us-east1 --detach
#
# To detach & delete the MIG backend of 'us-east1' Apigee Instance.
#     bash 4_manage_xlb_mig_backend.sh -r us-east1 --delete
#**
```

### 4.2. Manage XLB + NEG Backend: `bash 4_manage_xlb_neg_backend.sh -h`

This action is to create / attach / detach / delete the network-endpoint-group
(NEG) for the Apigee Instance's Service Attachment of the given region to the
backend-service of the load balancer.

Note: This script neither creates a new backend-service nor a new load balancer.
Instead, it creates/deletes network-endpoint-group (NEG) to Apigee's
Service Attachment Endpoint and attaches/detaches the NEG as a backend
to the existing backend service.

```shell
#**
#
# Usage:
#     bash 4_manage_xlb_neg_backend.sh -r|--region <REGION> [--create|--attach|--detach|--delete]
#         where, 'REGION' is the runtime region of the Apigee Instance.
#                '--create' will only create NEG for the Apigee Instance.
#                '--attach' will create NEG for the Apigee Instance and attach it as backend to XLB's backend service.
#                '--detach' will only remove NEG for the Apigee Instance as backend from XLB's backend service.
#                '--delete' will remove NEG for the Apigee Instance as backend from XLB's backend service and delete it.
#
# Examples:
# To create the NEG backend for 'us-east1' Apigee Instance.
#     bash 4_manage_xlb_neg_backend.sh -r us-east1 --create
#
# To create & attach the NEG backend of 'us-east1' Apigee Instance to backend service,
#     bash 4_manage_xlb_neg_backend.sh -r us-east1 --attach
#
# To detach the NEG backend of 'us-east1' Apigee Instance from backend service,
#     bash 4_manage_xlb_neg_backend.sh -r us-east1 --detach
#
# To detach & delete the NEG backend of 'us-east1' Apigee Instance.
#     bash 4_manage_xlb_neg_backend.sh -r us-east1 --delete
#**
```

### 5. Poll on Apigee LRO: `bash 5_wait_for_apigee_operation.sh -h`

This action is to check the status of the Apigee operation periodically
and wait for it to completion.

```shell
#**
#
# Usage:
#     bash 5_wait_for_apigee_operation.sh -o|--op <OPERATION_ID> [-t|--sleeptime <SLEEP_SECONDS>]
#         where, 'OPERATION_ID' is the Apigee Operation ID.
#                'SLEEP_SECONDS' is the wait time in seconds before rechecking
#                    the status of the Apigee Operation. Defaults to 30 seconds.
# Examples:
# To check the status of operation '51b915cc-7ddd-4402-b52c-90de0d1bb785' every 30 seconds (default).
#     bash 5_wait_for_apigee_operation.sh -o 51b915cc-7ddd-4402-b52c-90de0d1bb785
#
# To check the status of operation '51b915cc-7ddd-4402-b52c-90de0d1bb785' every 10 seconds,
#     bash 5_wait_for_apigee_operation.sh -o 51b915cc-7ddd-4402-b52c-90de0d1bb785 -t 10
#**
```
