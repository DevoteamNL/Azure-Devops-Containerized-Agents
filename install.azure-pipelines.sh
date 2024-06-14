#!/bin/bash

# define variables
# SUBSCRIPTION="000"
# RESOURCE_GROUP="jobs-sample"
# LOCATION="northcentralus"
# ENVIRONMENT="env-jobs-sample"
# JOB_NAME="azure-pipelines-agent-job"
# PLACEHOLDER_JOB_NAME="placeholder-agent-job"
# AZP_TOKEN="<AZP_TOKEN>"
# ORGANIZATION_URL="<ORGANIZATION_URL>"
# AZP_POOL="container-apps"
# CONTAINER_IMAGE_NAME="azure-pipelines-agent:1.0"
# CONTAINER_REGISTRY_NAME="<CONTAINER_REGISTRY_NAME>"

# parse the command line arguments
while getopts s:r:l:e:j:t:u:p:i:c: flag
do
    case "${flag}" in
        s) SUBSCRIPTION=${OPTARG};;
        r) RESOURCE_GROUP=${OPTARG};;
        l) LOCATION=${OPTARG};;
        e) ENVIRONMENT=${OPTARG};;
        j) JOB_NAME=${OPTARG};PLACEHOLDER_JOB_NAME=placeholder-${OPTARG};;
        t) AZP_TOKEN=${OPTARG};;
        u) ORGANIZATION_URL=${OPTARG};;
        p) AZP_POOL=${OPTARG};;
        i) CONTAINER_IMAGE_NAME=${OPTARG};;
        c) CONTAINER_REGISTRY_NAME=${OPTARG};;
    esac
done

# print the variables
echo "SUBSCRIPTION: $SUBSCRIPTION";
echo "RESOURCE_GROUP: $RESOURCE_GROUP";
echo "LOCATION: $LOCATION";
echo "ENVIRONMENT: $ENVIRONMENT";
echo "JOB_NAME: $JOB_NAME";
echo "PLACEHOLDER_JOB_NAME: $PLACEHOLDER_JOB_NAME";
echo "AZP_TOKEN: $AZP_TOKEN";
echo "ORGANIZATION_URL: $ORGANIZATION_URL";
echo "AZP_POOL: $AZP_POOL";
echo "CONTAINER_IMAGE_NAME: $CONTAINER_IMAGE_NAME";
echo "CONTAINER_REGISTRY_NAME: $CONTAINER_REGISTRY_NAME";

# login to azure
az login

# set the default subscription
az account set --subscription "$SUBSCRIPTION"

# ensure the containerapp extension is installed
az extension add --name containerapp --upgrade

# register the required providers
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights

# create the resource group
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION"

# create the environment
az containerapp env create \
    --name "$ENVIRONMENT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION"

# create the container registry
az acr create \
    --name "$CONTAINER_REGISTRY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Basic \
    --admin-enabled true

# create the container image
az acr build \
    --registry "$CONTAINER_REGISTRY_NAME" \
    --image "$CONTAINER_IMAGE_NAME" \
    --file "Dockerfile.azure-pipelines" \
    "https://github.com/Azure-Samples/container-apps-ci-cd-runner-tutorial.git"

# create the placeholder job
az containerapp job create -n "$PLACEHOLDER_JOB_NAMEPLACEHOLDER_JOB_NAME" -g "$RESOURCE_GROUP" --environment "$ENVIRONMENT" \
    --trigger-type Manual \
    --replica-timeout 300 \
    --replica-retry-limit 0 \
    --replica-completion-count 1 \
    --parallelism 1 \
    --image "$CONTAINER_REGISTRY_NAME.azurecr.io/$CONTAINER_IMAGE_NAME" \
    --cpu "2.0" \
    --memory "4Gi" \
    --secrets "personal-access-token=$AZP_TOKEN" "organization-url=$ORGANIZATION_URL" \
    --env-vars "AZP_TOKEN=secretref:personal-access-token" "AZP_URL=secretref:organization-url" "AZP_POOL=$AZP_POOL" "AZP_PLACEHOLDER=1" "AZP_AGENT_NAME=placeholder-agent" \
    --registry-server "$CONTAINER_REGISTRY_NAME.azurecr.io"

# start the placeholder job
az containerapp job start -n "$PLACEHOLDER_JOB_NAME" -g "$RESOURCE_GROUP"

# list the placeholder job
az containerapp job execution list \
    --name "$PLACEHOLDER_JOB_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --output table \
    --query '[].{Status: properties.status, Name: name, StartTime: properties.startTime}'


# create the job
az containerapp job create -n "$JOB_NAME" -g "$RESOURCE_GROUP" --environment "$ENVIRONMENT" \
    --trigger-type Event \
    --replica-timeout 1800 \
    --replica-retry-limit 0 \
    --replica-completion-count 1 \
    --parallelism 1 \
    --image "$CONTAINER_REGISTRY_NAME.azurecr.io/$CONTAINER_IMAGE_NAME" \
    --min-executions 0 \
    --max-executions 10 \
    --polling-interval 30 \
    --scale-rule-name "azure-pipelines" \
    --scale-rule-type "azure-pipelines" \
    --scale-rule-metadata "poolName=$AZP_POOL" "targetPipelinesQueueLength=1" \
    --scale-rule-auth "personalAccessToken=personal-access-token" "organizationURL=organization-url" \
    --cpu "2.0" \
    --memory "4Gi" \
    --secrets "personal-access-token=$AZP_TOKEN" "organization-url=$ORGANIZATION_URL" \
    --env-vars "AZP_TOKEN=secretref:personal-access-token" "AZP_URL=secretref:organization-url" "AZP_POOL=$AZP_POOL" \
    --registry-server "$CONTAINER_REGISTRY_NAME.azurecr.io"