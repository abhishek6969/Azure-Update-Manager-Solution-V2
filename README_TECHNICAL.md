# Technical Documentation

Deep-dive technical reference for the Azure Update Manager solution. This document explains the implementation details of each Terraform file and PowerShell script.

## Table of Contents

- [Terraform Files](#terraform-files)
- [PowerShell Scripts](#powershell-scripts)
- [Azure Resource Graph Queries](#azure-resource-graph-queries)
- [Authentication & Identity](#authentication--identity)
- [Event Flow](#event-flow)

---

## Terraform Files

### `main.tf` — Provider Configuration

Sets up the Azure RM provider and pinpoints which subscription to target.

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

**What it does:**
- Configures the Azure Resource Manager provider
- Points to the specific subscription via `var.subscription_id` (usually passed from `terraform.tfvars`)
- Requires provider version: `azurerm = 4.58.0`

**Key details:**
- The `features {}` block enables all default features for the azurerm provider
- All resource creation happens within this subscription context

---

### `backend.tf` — Remote State Management

Configures where Terraform state is stored — allowing team collaboration and preventing accidental local overwrites.

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-lirook-tfstate-prod"
    storage_account_name = "sttfstatelirookprod"
    container_name       = "tf-state-um"
    key                  = "terraform.tfstate"
  }
}
```

**What it does:**
- Stores Terraform state in a remote Azure Storage Account (not locally in `terraform.tfstate`)
- Enables multiple team members to safely run `terraform apply` without clobbering each other's changes
- Locks state during operations to prevent concurrent modifications

**Prerequisites:**
- The storage account `sttfstatelirookprod` must exist before running `terraform init`
- The container `tf-state-um` must be created inside that storage account
- Your Azure CLI credentials must have access to this storage account

**How to set up:**
```bash
az account set --subscription a1b2c3d4-e5f6-4a5b-8c7d-e9f0a1b2c3d4
az storage account create -g rg-lirook-tfstate-prod -n sttfstatelirookprod
az storage container create -n tf-state-um --account-name sttfstatelirookprod
```

---

### `variables.tf` — Input Variable Declarations

Defines all input variables the Terraform configuration accepts. These are placeholders for environment-specific values.

**Variables:**

| Variable | Type | Description |
|----------|------|-------------|
| `location` | string | Azure region (e.g., `germanywestcentral`) |
| `resource_group_name` | string | Name of the primary resource group |
| `automation_account_name` | string | Name of the Automation Account |
| `subscription_id` | string | Azure subscription ID |
| `default_tags` | map(string) | Default tags applied to all resources |

**Example from `terraform.tfvars`:**
```hcl
location                = "germanywestcentral"
resource_group_name     = "rg-lirook-updatemanagement"
automation_account_name = "aa-lirook-updatemanagement-dev"
subscription_id         = "a1b2c3d4-e5f6-4a5b-8c7d-e9f0a1b2c3d4"
default_tags = {
  CreateDate = "2026-03-17"
  CreatedBy  = "a10780809.11.1@tktenant.net"
}
```

---

### `automation_account.tf` — Automation Account & Webhooks

Creates the Automation Account (where runbooks execute) and the webhooks that Event Grid calls.

**Resources created:**

1. **`azurerm_automation_account.this`**
   - SKU: `Basic` (sufficient for runbook execution)
   - Identity: `SystemAssigned` (creates a managed identity automatically)
   - Network access: Public (can be restricted later)

2. **`azurerm_automation_webhook.pre_maintenance`**
   - Webhook URL: Generated at creation time (must be stored in Key Vault)
   - Runbook: `pre_maintenance`
   - Expiry: 2027-03-23 (expires in ~1 year)
   - Status: Enabled

3. **`azurerm_automation_webhook.post_maintenance`**
   - Webhook URL: Generated at creation time (must be stored in Key Vault)
   - Runbook: `post_maintenance`
   - Expiry: 2027-03-23
   - Status: Enabled

**Important:**
- Webhook URLs are **only available at creation time**. After `terraform apply`, retrieve them:
  ```bash
  terraform state show azurerm_automation_webhook.pre_maintenance
  terraform state show azurerm_automation_webhook.post_maintenance
  ```
- Store these URLs in Azure Key Vault (`kvlirook-prod-001`) as secrets for use in Event Grid subscriptions

---

### `runbooks.tf` — PowerShell Runbooks

Defines two runbooks that execute whenever Event Grid calls their webhooks.

**Runbooks created:**

1. **`azurerm_automation_runbook.pre_maintenance`**
   - Type: PowerShell72
   - Source: `scripts/rn-lirook-preMaintenance.ps1`
   - Runs: When a maintenance window **starts**
   - Purpose: Start any deallocated VMs and tag them

2. **`azurerm_automation_runbook.post_maintenance`**
   - Type: PowerShell72
   - Source: `scripts/rn-lirook-postMaintenance.ps1`
   - Runs: When a maintenance window **completes**
   - Purpose: Deallocate VMs that were started pre-maintenance

**Log settings (off by default):**
- `log_activity_trace_level = 0` — No tracing
- `log_progress = false` — Don't log progress
- `log_verbose = false` — Don't log verbose output

(Enable these if debugging runbook failures)

---

### `maintenance.tf` — Maintenance Configuration Schedules

Defines **four** maintenance configurations covering both Linux & Windows, and prod/non-prod environments.

**Configurations:**

1. **`mc-linux-nonprd`** — Linux Non-Production
   - Schedule: Monday, Wednesday, Friday at 06:00 CET
   - Duration: 3 hours 55 minutes

2. **`mc-linux-prd`** — Linux Production
   - Schedule: Monday, Wednesday, Friday at 06:00 CET
   - Duration: 3 hours 55 minutes

3. **`mc-windows-nonprd`** — Windows Non-Production
   - Schedule: Thursday, Friday at 06:00 CET
   - Duration: 3 hours 55 minutes

4. **`mc-windows-prd`** — Windows Production
   - Schedule: Friday at 06:00 CET
   - Duration: 3 hours 55 minutes

**Patch policy (all configurations):**
- Classifications: **Critical** and **Security** only
- Reboot: **IfRequired** (reboots only if patches require it)
- Windows KB filtering: None (all critical/security patches applied)
- Linux package filtering: None (all critical/security packages applied)

**Properties:**
- Scope: `InGuestPatch` (patches inside the OS, not just Azure)
- Visibility: `Custom` (limited to manually assigned VMs)
- User patch mode: `User` (patches as logged-in user, not system)

---

### `eventgrid.tf` — Event Grid System Topic

Creates a system topic that listens to maintenance events.

**Resource:**
- Name: `lirook-eg-topic`
- Type: `Microsoft.Maintenance.MaintenanceConfigurations`
- Bound to: `mc-windows-nonprd` maintenance configuration

**What it does:**
- Listens for Azure Update Manager events on the maintenance configuration
- When a maintenance window starts/completes, Event Grid fires events
- Events are JSON payloads containing the Maintenance Configuration ID and event type

**Event payload (example):**
```json
{
  "eventType": "Microsoft.Maintenance.PreMaintenanceEvent",
  "data": {
    "MaintenanceConfigurationId": "/subscriptions/a1b2.../resourceGroups/rg-lirook.../providers/Microsoft.Maintenance/maintenanceConfigurations/mc-windows-nonprd"
  }
}
```

---

### `eventgrid_subscriptions.tf` — Event Subscriptions

Routes Event Grid events to the Automation Account webhooks.

**Subscriptions created:**

1. **`es-pre-maintenance`**
   - Listens for: Pre-maintenance events
   - Sends to: Webhook URL from Key Vault (`webhook-url-pre-maintenance`)
   - Advanced filtering: Enabled (can filter by event type if needed)
   - Batch: Max 1 event per batch (fires immediately)

2. **`es-post-maintenance`**
   - Listens for: Post-maintenance events
   - Sends to: Webhook URL from Key Vault (`webhook-url-post-maintenance`)
   - Advanced filtering: Enabled
   - Batch: Max 1 event per batch

**How it works:**
- When Event Grid fires an event, it HTTP POSTs the JSON payload to the webhook URL
- The webhook URL is authenticated via a token (embedded in the URL — keep it secret!)
- Azure Automation receives the POST, extracts the JSON, and passes it to the runbook as `$WebhookData`

---

### `data.tf` — Key Vault Secret Lookups

Fetches webhook URLs from Azure Key Vault at apply time, avoiding hardcoding secrets in code.

**Data sources:**

1. **`azurerm_key_vault_secret.webhook_pre_maintenance`**
   - Secret name: `webhook-url-pre-maintenance`
   - Key Vault: `kvlirook-prod-001` (in `rg-lirook-sharedservices-prod-001`)

2. **`azurerm_key_vault_secret.webhook_post_maintenance`**
   - Secret name: `webhook-url-post-maintenance`
   - Key Vault: `kvlirook-prod-001`

**Prerequisites:**
- Both secrets must exist in Key Vault before running `terraform apply`
- After creating the webhooks, manually retrieve the URLs from Terraform state and store them here:
  ```bash
  az keyvault secret set --vault-name kvlirook-prod-001 \
    --name webhook-url-pre-maintenance \
    --value "https://a3b7c2d8f.webhook.aue.automation.azure.com/webhooks?token=..."
  ```

---

### `role_assignments.tf` — Managed Identity Permissions

Grants the Automation Account's managed identity two RBAC roles at the **tenant root management group** level.

**Roles assigned:**

1. **Reader**
   - Allows: Querying Azure Resource Graph across all subscriptions
   - Allows: Reading VM instance views (power state, tags)
   - Scope: Tenant root management group (applies to all subscriptions)

2. **Virtual Machine Contributor**
   - Allows: Starting VMs (`az vm start`)
   - Allows: Deallocating VMs (`az vm deallocate`)
   - Allows: Modifying tags (`az tag update`)
   - Scope: Tenant root management group

**Why tenant root?**
- The runbooks query VMs across multiple subscriptions
- Only tenant root scope allows cross-subscription access
- Requires Portal/CLI access with sufficient privileges to assign roles at management group level

---

## PowerShell Scripts

### `rn-lirook-preMaintenance.ps1` — Pre-Maintenance Runbook

Executes before patching begins. Starts any deallocated VMs so they can be patched.

**Parameters:**
- `$WebhookData` — JSON payload from Event Grid (passed automatically)
- `$TagName` — Tag key name (default: `StartedByPreMaintenance`)
- `$TagValue` — Tag value (default: `true`)
- `$MaintenanceConfigId` — Maintenance Configuration ID (extracted from webhook or manual)

**Execution steps:**

1. **Authenticate with Managed Identity**
   ```powershell
   az login --identity --output none
   ```
   - Uses the Automation Account's system-assigned managed identity
   - No credentials stored in the script

2. **Extract Maintenance Config ID from webhook payload**
   ```powershell
   $MaintenanceConfigId = $event.data.MaintenanceConfigurationId
   ```

3. **Install Resource Graph CLI extension**
   ```powershell
   az extension add --name resource-graph --only-show-errors 2>$null
   ```

4. **Query Azure Resource Graph to find assigned VMs**
   ```kusto
   maintenanceresources
   | where type == 'microsoft.maintenance/configurationassignments'
   | where tolower(properties.maintenanceConfigurationId) == tolower('...')
   | project resourceId = tostring(properties.resourceId)
   ```
   - Returns: Full Azure resource IDs of all VMs assigned to this maintenance config

5. **For each VM:**
   - Switch to the VM's subscription
   - Get power state: `az vm get-instance-view`
   - If `PowerState == "deallocated"`:
     - Start it: `az vm start --no-wait`
     - Tag it: `az tag update --operation Merge --tags "StartedByPreMaintenance=true"`
   - If already running: Skip

6. **Output summary**
   ```
   [INFO] Pre-maintenance complete. Processed N VM(s).
   ```

**No-wait operations:**
- `--no-wait` flag fires commands asynchronously (doesn't wait for completion)
- Allows runbook to finish quickly without waiting for VMs to fully boot

---

### `rn-lirook-postMaintenance.ps1` — Post-Maintenance Runbook

Executes after patching completes. Deallocates VMs that were started pre-maintenance.

**Execution steps:**

1–3. Same as pre-maintenance: Authenticate, extract config ID, install extension

4. **Query Azure Resource Graph (same KQL query as pre-maintenance)**
   - Finds all VMs assigned to this maintenance configuration

5. **For each VM:**
   - Switch to the VM's subscription
   - Check for tag: `StartedByPreMaintenance = true`
   - If tag exists:
     - Deallocate it: `az vm deallocate --no-wait`
     - Remove tag: `az tag update --operation Delete --tags "StartedByPreMaintenance=true"`
   - If tag doesn't exist: Skip (VMs were already running before maintenance)

6. **Output summary**
   ```
   [INFO] Post-maintenance complete. Processed N VM(s).
   ```

**Tag handoff mechanism:**
- Pre-maintenance: Tags VMs it starts
- Post-maintenance: Only deallocates VMs with that tag
- Ensures VMs that were already running don't get powered down

---

## Azure Resource Graph Queries

Both runbooks use the same KQL query to find assigned VMs:

```kusto
maintenanceresources
| where type == 'microsoft.maintenance/configurationassignments'
| where tolower(properties.maintenanceConfigurationId) == tolower('<MAINTENANCE_CONFIG_ID>')
| project resourceId = tostring(properties.resourceId)
```

**Explanation:**

| Part | Meaning |
|------|---------|
| `maintenanceresources` | Table containing all maintenance-related resources |
| `type == '...'` | Filters to only configuration assignment rows |
| `tolower(properties.maintenanceConfigurationId)` | Extracts the assigned config ID, case-insensitive |
| `project resourceId = ...` | Returns only the full Azure resource ID of each VM |

**Why Resource Graph?**
- Queries **all subscriptions** in one KQL statement
- Much faster than looping through subscriptions with `az vm list`
- Requires `Reader` role at tenant root

---

## Authentication & Identity

### System-Assigned Managed Identity

The Automation Account has a **system-assigned managed identity** created automatically.

**How it works:**
```powershell
az login --identity --output none
```
- No credentials, passwords, or tokens in the runbook
- Azure Automation runtime automatically injects the identity
- Identity has RBAC roles assigned directly (via `role_assignments.tf`)

**Advantages over alternatives:**
- No secrets to rotate
- No service principal passwords to manage
- Direct Azure AD integration
- Works seamlessly with `az cli` in runbooks

### RBAC Roles

Two roles are assigned at the **tenant root management group**:

1. **Reader**
   - Minimum permissions to query Resource Graph and read VM state
   - Allows: `az graph query`, `az vm get-instance-view`

2. **Virtual Machine Contributor**
   - Allows: Starting/stopping VMs, modifying tags
   - Allows: `az vm start`, `az vm deallocate`, `az tag update`

**Scope: Tenant Root Management Group**
- Applies to all subscriptions under your tenant
- Required because VMs are in different subscriptions
- Requires admin consent to assign

---

## Event Flow

### Complete sequence diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ MAINTENANCE WINDOW BEGINS                                           │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                 ┌──────────────────────────────┐
                 │ Azure Update Manager         │
                 │ (checks assigned VMs)        │
                 └──────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
                    ▼                       ▼
    ┌──────────────────────────┐  ┌──────────────────────────┐
    │ PreMaintenanceEvent      │  │ PostMaintenanceEvent     │
    │ (when window starts)     │  │ (when window completes)  │
    └──────────────────────────┘  └──────────────────────────┘
                    │                       │
                    ▼                       ▼
    ┌──────────────────────────┐  ┌──────────────────────────┐
    │ Event Grid System Topic  │  │ Event Grid System Topic  │
    │ (eventgrid_system_topic) │  │ (eventgrid_system_topic) │
    └──────────────────────────┘  └──────────────────────────┘
                    │                       │
                    ▼                       ▼
    ┌──────────────────────────┐  ┌──────────────────────────┐
    │ Event Subscription       │  │ Event Subscription       │
    │ (es-pre-maintenance)     │  │ (es-post-maintenance)    │
    └──────────────────────────┘  └──────────────────────────┘
                    │                       │
                    ▼                       ▼
    ┌──────────────────────────┐  ┌──────────────────────────┐
    │ HTTP POST (webhook URL)  │  │ HTTP POST (webhook URL)  │
    │ from Key Vault secret    │  │ from Key Vault secret    │
    └──────────────────────────┘  └──────────────────────────┘
                    │                       │
                    ▼                       ▼
    ┌──────────────────────────┐  ┌──────────────────────────┐
    │ Automation Account       │  │ Automation Account       │
    │ Receives webhook POST    │  │ Receives webhook POST    │
    └──────────────────────────┘  └──────────────────────────┘
                    │                       │
                    ▼                       ▼
    ┌──────────────────────────┐  ┌──────────────────────────┐
    │ pre_maintenance runbook  │  │ post_maintenance runbook │
    │ Executes PowerShell      │  │ Executes PowerShell      │
    └──────────────────────────┘  └──────────────────────────┘
                    │                       │
        ┌───────────┴───────────┐
        │                       │
        ▼                       ▼
    ┌──────────────────────┐  ┌──────────────────────┐
    │ • Query Resource     │  │ • Query Resource     │
    │   Graph for VMs      │  │   Graph for VMs      │
    │ • Find deallocated   │  │ • Find tagged VMs    │
    │ • Start them         │  │ • Deallocate them    │
    │ • Tag them           │  │ • Remove tags        │
    └──────────────────────┘  └──────────────────────┘
        │
        │ (VMs can now be patched)
        ▼
    ┌──────────────────────────────┐
    │ Azure Update Manager applies  │
    │ patches to running VMs        │
    └──────────────────────────────┘
```

### Key timing

- **Event Grid → Webhook:** ~1–2 seconds
- **Webhook → Runbook start:** ~2–5 seconds
- **Runbook execution:** 30 seconds–2 minutes (depends on VM count)
- **VM start/deallocate:** Queued asynchronously, happens in background

### Error handling

- If a VM fails to start: Runbook logs the error and continues with next VM
- If Resource Graph query fails: Runbook exits early with error message
- If webhook authentication fails: Event Grid retries up to 24 hours
- If runbook crashes: Webhook is considered failed; Event Grid retries

---

## Deployment checklist

Before running `terraform apply`:

- [ ] Storage account for Terraform state exists
- [ ] Azure Key Vault (`kvlirook-prod-001`) exists
- [ ] RBAC roles assigned at tenant root management group
- [ ] Resource group (`rg-lirook-updatemanagement`) exists
- [ ] VMs are assigned to maintenance configurations

After running `terraform apply`:

- [ ] Retrieve webhook URLs from Terraform state
- [ ] Store webhook URLs in Key Vault
- [ ] Update Event Grid subscriptions to point to correct maintenance configs (if needed)
- [ ] Test by running: `az vm list --subscription <sub> -o json | jq .[].name` to verify Resource Graph access

---

## Debugging tips

### View runbook logs
```bash
az automation job list --resource-group rg-lirook-updatemanagement \
  --automation-account-name aa-lirook-updatemanagement-dev \
  --query "[].name" -o tsv | tail -1 | xargs \
    az automation job output --resource-group rg-lirook-updatemanagement \
      --automation-account-name aa-lirook-updatemanagement-dev \
      --job-name
```

### Test runbook manually
```bash
az automation runbook list --resource-group rg-lirook-updatemanagement \
  --automation-account-name aa-lirook-updatemanagement-dev
```

### Query Resource Graph
```bash
az graph query -q "maintenanceresources | where type == 'microsoft.maintenance/configurationassignments' | take 5"
```

### Check Event Grid subscriptions
```bash
az eventgrid system-topic-event-subscription list \
  --resource-group rg-lirook-updatemanagement \
  --topic-name lirook-eg-topic
```

---

End of Technical Documentation
