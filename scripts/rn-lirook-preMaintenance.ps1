<#
.SYNOPSIS
    Pre-maintenance script: starts deallocated VMs assigned to a maintenance configuration and tags them.

.DESCRIPTION
    Queries Azure Resource Graph for VMs assigned to the specified maintenance configuration.
    Any deallocated VMs are started and tagged with "StartedByPreMaintenance = true" so they
    can be shut back down after maintenance completes.

    Uses az CLI instead of Az PowerShell modules.
#>

# ----- PARAMETERS -----
param(
    # Webhook payload — populated automatically when triggered by an Azure Automation webhook.
    [Parameter(Mandatory = $false)]
    [object]$WebhookData,

    # Tag key/value applied to VMs that this script starts so post-maintenance can shut them back down.
    [string]$TagName  = "StartedByPreMaintenance",
    [string]$TagValue = "true",

    # Maintenance Configuration ID — pass this manually when running the runbook without a webhook.
    # No default value; the script will error out if neither the webhook nor this parameter provides an ID.
    [Parameter(Mandatory = $false)]
    [string]$MaintenanceConfigId = ""
)




# ==================================================================================
# STEP 0 – Authenticate with the Automation Account's Managed Identity and extract
#           the Maintenance Configuration ID from the webhook payload.
# ==================================================================================

Write-Output "[INFO] Logging in with Managed Identity..."
az login --identity --output none

# Ensure the resource-graph CLI extension is installed (needed for 'az graph query').
az extension add --name resource-graph --only-show-errors 2>$null

if ($WebhookData) {
    # Extract the Maintenance Configuration ID from the webhook event payload.
    $events = $WebhookData.RequestBody | ConvertFrom-Json
    $event  = $events[0]
    $MaintenanceConfigId = $event.data.MaintenanceConfigurationId
    Write-Output "[INFO] Maintenance Configuration ID received from webhook."
}
elseif ([string]::IsNullOrWhiteSpace($MaintenanceConfigId)) {
    # Neither webhook nor manual parameter provided — cannot proceed.
    Write-Error "No WebhookData received and no MaintenanceConfigId parameter supplied. Please provide a Maintenance Configuration ID."
    throw "MaintenanceConfigId is required. Pass it as a parameter for manual runs or trigger via webhook."
}
else {
    Write-Output "[INFO] No webhook data. Using manually supplied MaintenanceConfigId."
}

Write-Output "[INFO] Maintenance Configuration ID: $MaintenanceConfigId"

# ==================================================================================
# STEP 1 – Query Azure Resource Graph (ARG) to find every VM assigned to the
#           maintenance configuration.
#
# Azure Resource Graph is a service that lets you run Kusto (KQL) queries across all
# your Azure subscriptions in one go — much faster than looping through subscriptions
# with az vm list.
#
# The query below:
#   • Looks at the "maintenanceresources" table (contains maintenance assignments).
#   • Filters rows whose type is "microsoft.maintenance/configurationassignments"
#     (these rows link a resource to a maintenance configuration).
#   • Filters further to keep only rows that point to OUR maintenance configuration
#     (using tolower() for case-insensitive comparison).
#   • Projects (selects) just the "properties.resourceId" column — i.e. the full
#     Azure resource ID of each VM assigned to this maintenance config.
# ==================================================================================

$kustoQuery = "maintenanceresources| where type == 'microsoft.maintenance/configurationassignments'| where tolower(properties.maintenanceConfigurationId) == tolower('$MaintenanceConfigId')| project resourceId = tostring(properties.resourceId)"

Write-Output "[INFO] Running Azure Resource Graph query to find assigned VMs..."

# az graph query sends the KQL query to Azure Resource Graph and returns JSON.
# Join the output lines into a single string so ConvertFrom-Json can parse it.
$graphJson = (az graph query -q $kustoQuery --output json) -join "`n"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Azure Resource Graph query failed. Exit code: $LASTEXITCODE"
    return
}
[array]$graphResults = ($graphJson | ConvertFrom-Json).data

# If no rows came back, there are no VMs assigned — nothing to do.
if ($graphResults.Count -eq 0) {
    Write-Output "[WARN] No VMs found for maintenance configuration."
    return   # Exit the script early.
}

# Pull out just the resourceId strings into a simple array.
[array]$resourceIds = $graphResults | ForEach-Object { $_.resourceId }
Write-Output "[INFO] Found $($resourceIds.Count) VM(s) assigned to the maintenance configuration."

# ==================================================================================
# STEP 2 – Loop through every resource ID, check if the VM is deallocated, and if so
#           start it and tag it.
# ==================================================================================

# If a command throws an error, continue so one VM failure doesn't stop the rest.
$ErrorActionPreference = "Continue"

foreach ($resourceId in $resourceIds) {

    # --- 2a. Parse the resource ID ---
    # A VM resource ID looks like:
    #   /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<name>
    #
    # Split by "/" to extract parts by position.
    #   parts[2] → subscription ID
    #   parts[4] → resource group name
    #   parts[8] → VM name
    $parts = $resourceId.Split("/")

    $subscriptionId = $parts[2]   # e.g. "a1b2c3d4-e5f6-..."
    $resourceGroup  = $parts[4]   # e.g. "rg-lirook-updatemanagement"
    $vmName         = $parts[8]   # e.g. "vm-web-01"

    # --- 2b. Switch subscription context if needed ---
    $currentSub = (az account show --query "id" -o tsv 2>$null)
    if ($currentSub -ne $subscriptionId) {
        Write-Output "[INFO] Switching to subscription $subscriptionId..."
        az account set --subscription $subscriptionId
    }

    # --- 2c. Get the VM's current power state ---
    # az vm get-instance-view returns the instance view including power state.
    $instanceViewJson = (az vm get-instance-view `
        --resource-group $resourceGroup `
        --name $vmName `
        --output json) -join "`n"

    $instanceView = $instanceViewJson | ConvertFrom-Json

    # The statuses array contains objects with a "code" property.
    # We want the one starting with "PowerState/".
    $powerState = ($instanceView.instanceView.statuses | Where-Object { $_.code -like "PowerState/*" }).code

    # --- 2d. If deallocated → start the VM and tag it ---
    if ($powerState -eq "PowerState/deallocated") {
        Write-Output "[ACTION] Starting deallocated VM: $vmName ..."

        # --no-wait fires the start command without waiting for the VM to fully boot.
        az vm start --resource-group $resourceGroup --name $vmName --no-wait

        # Tag the VM so we remember we started it.
        # az tag update with --operation Merge adds/updates only the specified tags.
        az tag update --resource-id $resourceId --operation Merge --tags "$TagName=$TagValue" --output none

        Write-Output "[DONE] Started and tagged $vmName ($TagName=$TagValue)."
    }
    else {
        # VM is already running (or stopped-but-still-allocated, etc.) — no action needed.
        Write-Output "[SKIP] VM $vmName is not deallocated ($powerState). No action needed."
    }
}

Write-Output "[INFO] Pre-maintenance complete. Processed $($resourceIds.Count) VM(s)."
