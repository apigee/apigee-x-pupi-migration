# Apigee-X Instance Recreation with Zero Downtime

This project provides scripts that you can use to recreate Apigee instances without
any downtime or any data-loss. For more information and use case details, see
[Recreating an Apigee instance with zero downtime](https://cloud.google.com/apigee/docs/api-platform/system-administration/instance-recreate).

--------------------------------------------------------------------------------

## Overview

To recreate an instance with zero downtime and no data loss, you need to first create a new instance in a
new (expanded) region and direct API traffic to that new instance. Then, you can drain down the existing
instance, delete it, and recreate it in the same region as the one you deleted.

Apigee has provided a set of scripts in this project that perform all of the required steps to recreate an
instance. 

The basic steps are:

1. Update a configuration script, `source.sh`.
2. Create, configure, and direct API traffic to a new, temporary Apigee instance in a new region.
3. Delete the original instance (the instance you are replacing).
4. Create, configure, and direct API traffic to a new instance in the same region as the original instance.
5. Delete the temporary instance.

### 1. Update `source.sh`

This script defines a templated function that you must copy and modify. When you are finished, the script will have
two functions: one with parameter values for the existing instance (the one you are replacing),
and one for a new, temporary instance. The scripts you will run later call these functions to perform
their tasks.

The basic steps are:

1. Fill in your Google Cloud project ID at the top of the `source.sh` script.
2. Copy the function block.
3. Change the name of the first function to: `INIT_REGION_${REGION_ID}`, where `REGION_ID` is
the name of the region in which you will create a temporary instance. This region cannot be
the same as the region in which your existing instance is provisioned. For example, if
the new region is `us-east1`, rename the function:

    `INIT_REGION_US_EAST1`

    You must follow the pattern where the region name is all caps with an underscore `_`
    instead of a hyphen. For example: `US_EAST1`

4. Fill in values for the templated variables. See a brief description of each variable below.
5. Change the name of the second function and configure it for the region where the existing
instance is provisioned. For example, if the existing region is `us-west1`, rename the second
function:

    `INIT_REGION_US_WEST1`

    Follow the same capitalization pattern as before.

Following is a summary of the values you must provide in the templated functions:


-   `PROJECT_ID`: Project ID of Apigee organization.
-   `INSTANCE_NAME`: Name of the Apigee instance to create / delete.
-   `RUNTIME_LOCATION`: Actual GCP region of the Apigee instance.
-   `DISK_KEY_PROJECT_ID`: Project ID of KMS Key used for disk encryption.
-   `DISK_KEY_RING_NAME`: Name of the KMS Key Ring used for disk encryption. If
    it doesn't already exist, it will be created automatically. It will be
    reused if it already exists.
-   `DISK_KEY_NAME`: Name of the KMS Key used for disk encryption. If it doesn't
    already exist, it will be created automatically. It will be reused if it
    already exists.
-   `IP_RANGE`: ***[OPTIONAL]*** Comma separated values of /22 & /28 IP Ranges.
    If provided, make sure the ranges are part of CIDR blocks allocated to the
    service networking. ***See
    [Configure service networking](https://cloud.google.com/apigee/docs/api-platform/get-started/configure-service-networking)
    for more details.***
-   `CONSUMER_ACCEPT_LIST`: ***[OPTIONAL]*** Comma separated values of GCP
    projects for PSC allow-listing.
-   `ENVIRONMENTS_LIST`: Comma separated values of Environments to attach
    to/detach from the Apigee instance.

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

### 2. Provision the new, temporary instance

Run the following scripts to provision the new, temporary Apigee instance. The script
handles environment configuration and network routing so that API traffic is routed to
the new instance.


Important: Before doing this step, you must create network space in your project with additional IP ranges of /22 and /28 blocks.
For details, see [Prerequisites](https://cloud.google.com/apigee/docs/api-platform/system-administration/instance-recreate#prerequisites).

Note: While each script periodically checks for the completion of Apigee's
long-running-operations (LRO), you can always monitor their status by running: \
**`bash 5_wait_for_apigee_operation.sh -o ${OPERATION_ID}`**

#### ► Using Managed Instance Group (MIG)

Run these scripts if the existing instance was configured with a MIG (most common):

```shell
1. REGION=##The Google Cloud region to install the new, temporary Apigee instance. Example: "us-east1"##
2. bash 1_manage_instance.sh -r ${REGION} --create
   # This script can take up to an hour to complete.
3. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --count 2 --reserve
   # If you reserve NAT Addresses, add them to your target allow-listing before proceeding.
4. bash 3_manage_environments.sh -r ${REGION} --attach
5. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --create
6. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --attach
```

#### ► Using Network Endpoint Group (NEG)

Run these scripts if the existing instance was configured with a NEG (uncommon):

```shell
1. REGION=##The Google Cloud region to install the new, temporary Apigee instance. Example: "us-east1"##
2. bash 1_manage_instance.sh -r ${REGION} --create
3. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --count 2 --reserve
   # If you reserve NAT Addresses, add them to your target allow-listing before proceeding.
4. bash 3_manage_environments.sh -r ${REGION} --attach
5. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --create
6. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --attach
```

### 3. Remove the existing Apigee instance

Run the following scripts to drain down and remove the existing instance.


Note: While each script periodically checks for the completion of Apigee's
long-running-operations (LRO), you can always monitor their status by running \
`bash 5_wait_for_apigee_operation.sh -o ${OPERATION_ID}`

#### ► Using Managed-Instance-Group (MIG)

Run these scripts if the existing instance was configured with a MIG (most common):


```shell
1. REGION=##The Google Cloud region where the existing instance that you are replacing is deployed. Example: "us-west1"##
2. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --detach
3. bash 3_manage_environments.sh -r ${REGION} --detach
4. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --release
   # If you reserved NAT Addresses, remove them from your target allow-listing.
5. bash 1_manage_instance.sh -r ${REGION} --delete
6. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --delete
```

#### ► Using Network-Endpoint-Group (NEG)

Run these scripts if the existing instance was configured with a NEG (uncommon):


```shell
1. REGION=##The Google Cloud region where the existing instance that you are replacing is deployed. Example: "us-west1"##
2. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --detach
3. bash 3_manage_environments.sh -r ${REGION} --detach
4. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --release
   # If you reserved NAT Addresses, remove them from your target allow-listing.
5. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --delete
6. bash 1_manage_instance.sh -r ${REGION} --delete
```


### 4. Provision a new instance in the original region

Run the following scripts to provision a new Apigee instance (the replacement instance) in the original region. The script
handles environment configuration and network routing so that API traffic is routed to
the new instance.


Note: While each script periodically checks for the completion of Apigee's
long-running-operations (LRO), you can always monitor their status by running \
**`bash 5_wait_for_apigee_operation.sh -o ${OPERATION_ID}`**

#### ► Using Managed Instance Group (MIG)

Run these scripts if the original instance was configured with a MIG (most common):

```shell
1. REGION=##The Google Cloud region to install the new Apigee instance. Example: "us-west1"##
2. bash 1_manage_instance.sh -r ${REGION} --create
3. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --count 2 --reserve
   # If you reserve NAT Addresses, add them to your target allow-listing before proceeding.
4. bash 3_manage_environments.sh -r ${REGION} --attach
5. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --create
6. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --attach
```

#### ► Using Network Endpoint Group (NEG)

Run these scripts if the original instance was configured with a NEG (uncommon):

```shell
1. REGION=##The Google Cloud region to install the new Apigee instance. Example: "us-west1"##
2. bash 1_manage_instance.sh -r ${REGION} --create
3. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --count 2 --reserve
   # If you reserve NAT Addresses, add them to your target allow-listing before proceeding.
4. bash 3_manage_environments.sh -r ${REGION} --attach
5. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --create
6. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --attach
```


### 5. Remove the temporary Apigee instance

Run the following scripts to drain down and remove the temporary instance.


Note: While each script periodically checks for the completion of Apigee's
long-running-operations (LRO), you can always monitor their status by running \
**`bash 5_wait_for_apigee_operation.sh -o ${OPERATION_ID}`**

#### ► Using Managed-Instance-Group (MIG)

Run these scripts if the original instance was configured with a MIG (most common):


```shell
1. REGION=##The Google Cloud region where the temporary instance is deployed. Example: "us-east1"##
2. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --detach
3. bash 3_manage_environments.sh -r ${REGION} --detach
4. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --release
   # If you reserved NAT Addresses, remove them from your target allow-listing.
5. bash 1_manage_instance.sh -r ${REGION} --delete
6. bash 4_manage_xlb_mig_backend.sh -r ${REGION} --delete
```

#### ► Using Network-Endpoint-Group (NEG)

Run these scripts if the original instance was configured with a NEG (uncommon):


```shell
1. REGION=##The Google Cloud region where the temporary instance is deployed. Example: "us-east1"##
2. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --detach
3. bash 3_manage_environments.sh -r ${REGION} --detach
4. [OPTIONAL] bash 2_manage_nat_address.sh -r ${REGION} --release
   # If you reserved NAT Addresses, remove them from your target allow-listing.
5. bash 4_manage_xlb_neg_backend.sh -r ${REGION} --delete
6. bash 1_manage_instance.sh -r ${REGION} --delete
```


--------------------------------------------------------------------------------

## Script Details

### 1. Manage Instance: `bash 1_manage_instance.sh -h`

This action is to manage creation / deletion of Apigee Instance for the given
GCP region. While deleting, ensure that you at least have one
other region taking traffic to avoid any interruptions/data-loss.

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
Apigee Instance for the given region. You should add the NAT IPs from
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
and wait for it to complete.

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
