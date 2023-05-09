# Apigee-X Instance Recreation with downtime and data loss.

## Overview

To recreate an instance with downtime and data loss, you need to drain down and
delete the existing instance. Create a new instance in the same region and
direct API traffic to the new instance.

Apigee has provided a set of scripts that perform all of the required steps to
recreate an instance.

The basic steps are:

1.  Update a configuration script, `source.sh`.
2.  Delete the original instance (the instance you are replacing).
3.  Create, configure, and direct API traffic to a new instance in the same
    region as the original instance.

### 1. Update `source.sh`

This script defines a templated function that you must copy and modify. The
scripts you will run later call these functions to perform their tasks.

The basic steps are:

1.  Fill in your Google Cloud project ID at the top of the `source.sh` script.
2.  Change the name of the first function to: `INIT_REGION_${REGION_ID}`, where
    `REGION_ID` is the name of the region of the existing instance. For example,
    if the region is `us-east1`, rename the function:

    `INIT_REGION_US_EAST1`

    You must follow the pattern where the region name is all caps with an
    underscore `_` instead of a hyphen. For example: `US_EAST1`

3.  Fill in values for the templated variables. See a brief description of each
    variable [here](./README.md#configuration-script)

### 2. Remove the existing Apigee instance

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

### 3. Provision a new instance in the original region

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
