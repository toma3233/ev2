#!/bin/bash
set -euo

# The contents of this script are tasks that can't yet be done with Ev2+ARM. As
# these features become available in Ev2/ARM, we should remove this script.
PAV2_VALUE_NAME_BASE=aksblp
pav_sa_name="${RESOURCE_NAME_PREFIX_NODASH}${PAV2_VALUE_NAME_BASE}${REGION_SHORT_NAME}"

# create aksusage table in PAv2 storage account
aksusage_table_name="aksusage"
echo "Creating "${aksusage_table_name}" table in PAV2 storage account"
aksusage_table_created="$(az storage table create -n "${aksusage_table_name}" --account-name "${pav_sa_name}" --auth-mode login -o json | jq -r '.created')"
if [[ "$aksusage_table_created" == "" ]]; then
    echo "failed to create "${aksusage_table_name}" table in pav storage account "${pav_sa_name}""
    exit 1
fi
echo "Created "${aksusage_table_name}" table in pav storage account with name $pav_sa_name\n"

# create aksusage queue in PAv2 storage account
aksusage_queue_name="aksusage"
echo "Creating "${aksusage_queue_name}" queue in PAv2 storage account"
arousage_queue_created="$(az storage queue create -n "${aksusage_queue_name}" --account-name "${pav_sa_name}" --auth-mode login -o json | jq -r '.created')"
if [[ "$arousage_queue_created" == "" ]]; then
    echo "failed to create "${aksusage_queue_name}" queue in pav storage account "${pav_sa_name}""
    exit 1
fi
echo "Created "${aksusage_queue_name}" queue in pav storage account with name $pav_sa_name\n"

# create akserrors table in PAv2 storage account
akserrors_table_name="akserrors"
echo "Creating "${akserrors_table_name}" table in PAv2 storage account"
akserrors_table_created="$(az storage table create -n "${akserrors_table_name}" --account-name "${pav_sa_name}" --auth-mode login -o json | jq -r '.created')"
if [[ "$akserrors_table_created" == "" ]]; then
    echo "failed to create "${akserrors_table_name}" table in pav storage account "${pav_sa_name}""
    exit 1
fi
echo "Created "${akserrors_table_name}" table in pav storage account with name $pav_sa_name\n"

# create akserrors queue in PAv2 storage account
akserrors_queue_name="akserrors"
echo "Creating "${akserrors_queue_name}" queue in PAv2 storage account"
akserrors_queue_created="$(az storage queue create -n "${akserrors_queue_name}" --account-name "${pav_sa_name}" --auth-mode login -o json | jq -r '.created')"
if [[ "$akserrors_queue_created" == "" ]]; then
    echo "failed to create "${akserrors_queue_name}" queue in pav storage account "${pav_sa_name}""
    exit 1
fi
echo "Created "${akserrors_queue_name}" queue in pav storage account with name $pav_sa_name\n"