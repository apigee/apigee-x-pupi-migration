# Apigee-X Instance Recreation with Zero Downtime and Zero data loss with existing multi region setup.

For more information and use case details, see
[Recreating an Apigee instance with zero downtime](https://cloud.google.com/apigee/docs/api-platform/system-administration/instance-recreate).

--------------------------------------------------------------------------------

## Overview

This solution is ideal for you, if you already have a multi region Apigee setup
and are okay with using Apigee temporarily with one less region. You need to
make sure the Apigee instances you are temporarily routing the existing instance
traffic to has all the Apigee environments attached as the instance being
recreated. To recreate an instance with zero downtime and no data loss, you need
to direct API traffic to that other Apigee instances. Then, you can drain down
the existing instance, delete it, and recreate it in the same region as the one
you deleted.

Apigee has provided a set of scripts in this project that perform all of the
required steps to recreate an instance.

The basic steps are:

1.  Update a configuration script, `source.sh`.
2.  Direct API traffic to a other existing Apigee instances.
3.  Drain and Delete the original instance (the instance you are replacing).
4.  Create, configure, and direct API traffic to a new instance in the same
    region as the original instance.

### 1. Update `source.sh`

This script defines a templated function that you must copy and modify. When you
are finished, the script will have multiple functions: one with parameter values
for the existing instance (the one you are replacing), rest of the functions
will be for other regions where the traffic is temporarily being redirected
to.The scripts you will run later call these functions to perform their tasks.

The basic steps are:

1.  Fill in your Google Cloud project ID at the top of the `source.sh` script.
2.  Copy the function block.
3.  Fill in values for the templated variables. See a brief description of each
    variable [here](./README.md#configuration-script)

4.  Change the name of the function and configure it for the region where the
    existing instance is provisioned. For example, if the existing region is
    `us-west1`, rename the function:

    `INIT_REGION_US_WEST1`

    Follow the same capitalization pattern as before.

    Fill in values for the templated variables. See a brief description of each
    variable [here](./README.md#configuration-script)

5.  Copy the function block.

6.  Fill in values for the templated variables. See a brief description of each
    variable [here](./README.md#configuration-script).

7.  Use the
    [API](https://cloud.google.com/apigee/docs/reference/apis/apigee/rest/v1/organizations.instances.attachments/list)
    to get list of envs attached to this instance and the instance being
    recreated. Compare them to find the environments that are not attached to
    this existing instance but attached to the instance being recreated.

8.  Change the name of the function and configure it for the region where other
    Apigee instance is provisioned. Make sure to only include environments
    calculated in above step in "ENVIRONMENTS_LIST" template variable template
    variable. For example, if the region is `us-east1`, rename the second
    function:

    `INIT_REGION_US_EAST1`

    Follow the same capitalization pattern as before.

    Fill in values for the templated variables. See a brief description of each
    variable [here](./README.md#configuration-script)

9.  Repeat steps 5-8 for all other remaining regions which will handle the
    traffic for the instance being recreated.

### 2. Make sure other instances are capable of handling traffic.

You need to make sure other instances which will handle the traffic has all the
environments of the instance being created attached to them.

Run this command on the instances which will serve traffic of the instance being
recreated to attach the environments.

```shell
1. REGION=##The Google Cloud region to install the new Apigee instance. Example: "us-west1"##
2. bash 3_manage_environments.sh -r ${REGION} --attach
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

### 5. Revert any additional environments attached to other instances.(optional)

Run this command on the instances to which additional environments were
attached.

```shell
1. REGION=##The Google Cloud region to install the new Apigee instance. Example: "us-west1"##
2. bash 3_manage_environments.sh -r ${REGION} --detach
```
