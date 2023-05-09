# Instance Recreation

Apigee instances created before January 25, 2022, do not have sufficient
internet protocol (IP) address space to allow Apigee workloads to scale to
handle increasing API traffic and/or to allow you to add more than 10
environments to an instance.

On January 24, 2022, Apigee introduced an enhancement to address this problem.
The enhancement reduces the IP range required to peer your VPC network with
Apigee and uses privately used public IPs (PUPI) to allow workloads to scale to
higher limits.

This project provides multiple options to recreate Apigee instance in order to
address the IP issue and take advantage of PUPI with Apigee.

*   ***[Recreate instance with no downtime and no data loss](./recreate_with_no_downtime_and_no_data_loss.md)***:
    This is the recommended approach. Ideal if you are already multi region
    Apigee but are not okay with other existing regions handling API requests
    temporarily and don't want any data loss or downtime. This requires you to
    create a new temporary Apigee Instance in a different region than the
    existing ones.

*   ***[Recreate instance with downtime and data loss - reuse other existing
    instances](./recreate_with_no_downtime_and_no_data_existing_multi_region.md)***:
    This is the recommended approach if you are already multi region Apigee and
    are okay with other existing regions handling all the API requests
    temporarily and don't want any data loss and downtime. This approach does
    not require you to create any temporary Apigee instances.

*   ***[Recreate instance with downtime but with no data loss](./recreate_with_downtime_and_no_data_loss.md)***:
    This is good if you are okay with downtime (probably suitable for
    non-production Apigee organizations) but still want to retain the runtime
    data. This requires you to create a new temporary Apigee Instance in a
    different region than the existing ones. However, traffic re-routing is not
    required.

*   ***[Recreate instance with downtime and data loss](./recreate_with_downtime_and_data_loss.md)***:
    This is good if you are okay with downtime and data loss(probably suitable
    for non-production Apigee organizations).

Apigee provides configuration scripts and scripts to perform all the required
tasks for the migration. Read below about the configuration and the scripts.

# Configuration Script

The script [source.sh](./source.sh) defines a templated function that you must
copy and modify. The scripts you will run later call these functions to perform
their tasks.

Following is a summary of the values you must provide in the templated
functions:

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
-   `NEG_NAME`: Name of the PSC network-endpoint-group for Apigee
    service-attachment. ***[Required only when using PSC NEG]***

--------------------------------------------------------------------------------

## Script Details

### 1. Manage Instance: `bash 1_manage_instance.sh -h`

This action is to manage creation / deletion of Apigee Instance for the given
GCP region. While deleting, ensure that you at least have one other region
taking traffic to avoid any interruptions/data-loss.

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
Apigee Instance for the given region. You should add the NAT IPs from the output
of this script to their target allow-listing while reserving them.

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

This action is to attach / detach all the environments to Apigee Instance for
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
Instead, it creates/deletes managed-instance-group (MIG) that proxies traffic to
Apigee Endpoint, and attaches/detaches the MIG as a backend to the existing
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
Instead, it creates/deletes network-endpoint-group (NEG) to Apigee's Service
Attachment Endpoint and attaches/detaches the NEG as a backend to the existing
backend service.

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

This action is to check the status of the Apigee operation periodically and wait
for it to complete.

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
