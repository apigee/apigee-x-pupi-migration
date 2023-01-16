# Apigee-X Instance Recreation with Zero Downtime and Zero data loss.

For more information and use case details, see
[Recreating an Apigee instance with zero downtime](https://cloud.google.com/apigee/docs/api-platform/system-administration/instance-recreate).

--------------------------------------------------------------------------------

## Overview

To recreate an instance with zero downtime and no data loss, you need to first
create a new instance in a new (expanded) region and direct API traffic to that
new instance. Then, you can drain down the existing instance, delete it, and
recreate it in the same region as the one you deleted.

Apigee has provided a set of scripts in this project that perform all of the
required steps to recreate an instance.

The basic steps are:

1.  Update a configuration script, `source.sh`.
2.  Create, configure, and direct API traffic to a new, temporary Apigee
    instance in a new region.
3.  Delete the original instance (the instance you are replacing).
4.  Create, configure, and direct API traffic to a new instance in the same
    region as the original instance.
5.  Delete the temporary instance.

### 1. Update `source.sh`

This script defines a templated function that you must copy and modify. When you
are finished, the script will have two functions: one with parameter values for
the existing instance (the one you are replacing), and one for a new, temporary
instance. The scripts you will run later call these functions to perform their
tasks.

The basic steps are:

1.  Fill in your Google Cloud project ID at the top of the `source.sh` script.
2.  Copy the function block.
3.  Change the name of the first function to: `INIT_REGION_${REGION_ID}`, where
    `REGION_ID` is the name of the region in which you will create a temporary
    instance. This region cannot be the same as the region in which your
    existing instance is provisioned. For example, if the new region is
    `us-east1`, rename the function:

    `INIT_REGION_US_EAST1`

    You must follow the pattern where the region name is all caps with an
    underscore `_` instead of a hyphen. For example: `US_EAST1`

4.  Fill in values for the templated variables. See a brief description of each
    variable [here](./README.md#configuration-script)

5.  Change the name of the second function and configure it for the region where
    the existing instance is provisioned. For example, if the existing region is
    `us-west1`, rename the second function:

    `INIT_REGION_US_WEST1`

    Follow the same capitalization pattern as before.

    Fill in values for the templated variables. See a brief description of each
    variable [here](./README.md#configuration-script)

### 2. Provision the new, temporary instance

Run the following scripts to provision the new, temporary Apigee instance. The
script handles environment configuration and network routing so that API traffic
is routed to the new instance.

Important: Before doing this step, you must create network space in your project
with additional IP ranges of /22 and /28 blocks. For details, see
[Prerequisites](https://cloud.google.com/apigee/docs/api-platform/system-administration/instance-recreate#prerequisites).

Note: While each script periodically checks for the completion of Apigee's
long-running-operations (LRO), you can always monitor their status by running: \
**`bash 5_wait_for_apigee_operation.sh -o ${OPERATION_ID}`**

#### ► Using Managed Instance Group (MIG)

Run these scripts if the existing instance was configured with a MIG (most
common):

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

Run these scripts if the existing instance was configured with a MIG (most
common):

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

Run the following scripts to provision a new Apigee instance (the replacement
instance) in the original region. The script handles environment configuration
and network routing so that API traffic is routed to the new instance.

Note: While each script periodically checks for the completion of Apigee's
long-running-operations (LRO), you can always monitor their status by running \
**`bash 5_wait_for_apigee_operation.sh -o ${OPERATION_ID}`**

#### ► Using Managed Instance Group (MIG)

Run these scripts if the original instance was configured with a MIG (most
common):

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

Run these scripts if the original instance was configured with a MIG (most
common):

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
