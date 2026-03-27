<#
.SYNOPSIS
    Post-maintenance script: deallocates VMs that were started by the pre-maintenance script.

.DESCRIPTION
    Queries Azure Resource Graph for VMs assigned to the specified maintenance configuration.
    Any VM that carries the tag stamped by the pre-maintenance script (StartedByPreMaintenance = true)
    is deallocated and the tag is removed.

    Uses az CLI instead of Az PowerShell modules.
#>

# ----- PARAMETERS -----
param(
    # Webhook payload — populated automatically when triggered by an Azure Automation webhook.
    [Parameter(Mandatory = $false)]
    [object]$WebhookData,

    # Tag key/value used to identify VMs that were started by the pre-maintenance script.
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
# STEP 1 – Query Azure Resource Graph to find every VM assigned to the maintenance
#           configuration (same query the pre-maintenance script uses).
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

if ($graphResults.Count -eq 0) {
    Write-Output "[WARN] No VMs found for maintenance configuration."
    return
}

[array]$resourceIds = $graphResults | ForEach-Object { $_.resourceId }
Write-Output "[INFO] Found $($resourceIds.Count) VM(s) assigned to the maintenance configuration."

# ==================================================================================
# STEP 2 – Loop through every resource ID. If the VM has the pre-maintenance tag,
#           deallocate it and remove the tag.
# ==================================================================================

foreach ($resourceId in $resourceIds) {

    # --- 2a. Parse the resource ID ---
    $parts = $resourceId.Split("/")

    $subscriptionId = $parts[2]
    $resourceGroup  = $parts[4]
    $vmName         = $parts[8]

    # --- 2b. Switch subscription context if needed ---
    $currentSub = (az account show --query "id" -o tsv 2>$null)
    if ($currentSub -ne $subscriptionId) {
        Write-Output "[INFO] Switching to subscription $subscriptionId..."
        az account set --subscription $subscriptionId
    }

    # --- 2c. Check whether the VM carries the pre-maintenance tag ---
    $tagJson = (az tag list --resource-id $resourceId --output json) -join "`n"
    $tagData = ($tagJson | ConvertFrom-Json).properties.tags

    if ($tagData.$TagName -eq $TagValue) {

        Write-Output "[ACTION] Deallocating VM: $vmName (tagged by pre-maintenance)..."

        # Stop (deallocate) the VM without waiting for completion.
        az vm deallocate --resource-group $resourceGroup --name $vmName --no-wait

        # Remove the pre-maintenance tag so it won't be picked up again.
        az tag update --resource-id $resourceId --operation Delete --tags "$TagName=$TagValue" --output none

        Write-Output "[DONE] Deallocated and removed tag from $vmName."
    }
    else {
        Write-Output "[SKIP] VM $vmName does not have the pre-maintenance tag. No action needed."
    }
}

Write-Output "[INFO] Post-maintenance complete. Processed $($resourceIds.Count) VM(s)."
