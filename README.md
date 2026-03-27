# Azure Update Manager

Automated patch management solution for Azure Virtual Machines using Azure Update Manager, Automation Account runbooks, and Event Grid for event-driven pre/post maintenance orchestration.

## Solution Overview

Azure Update Manager handles OS patching for both Linux and Windows VMs across production and non-production environments. Maintenance windows are defined with schedules, and the solution hooks into the maintenance lifecycle via Event Grid to run custom logic before and after patches are applied.

### How It Works

1. **Maintenance Configurations** define patch schedules for four environments:
   - Linux Non-Production — Mon/Wed/Fri at 06:00 CET
   - Linux Production — Mon/Wed/Fri at 06:00 CET
   - Windows Non-Production — Thu/Fri at 06:00 CET
   - Windows Production — Fri at 06:00 CET

   Each schedule targets **Critical** and **Security** patches only, reboots if required, and allows up to ~4 hours for completion.

2. **Event Grid** listens for maintenance events on the subscription. When Azure Update Manager starts or completes a maintenance window, Event Grid captures pre and post maintenance events via a system topic bound to the maintenance configuration.

3. **Event Subscriptions** route these events to Automation Account webhooks. Currently, event subscriptions are only configured for the **non-production** maintenance configurations. Production event subscriptions can be added later once the solution is validated.

4. **Webhook URLs** are stored as secrets in Azure Key Vault (`kvlirook-prod-001`) and referenced at deploy time, keeping sensitive endpoint URLs out of source control.

### The Problem the Runbooks Solve

Some VMs may be deallocated (shut down to save costs) when a maintenance window begins. Azure Update Manager cannot patch a VM that isn't running. The runbooks handle this automatically:

- **Pre-maintenance** starts any deallocated VMs so they can be patched.
- **Post-maintenance** shuts them back down so they don't incur unnecessary compute costs.

### Pre-Maintenance Runbook (`rn-lirook-preMaintenance`)

When a maintenance window is about to begin, Event Grid fires a webhook that triggers this runbook. It:

1. **Authenticates** using the Automation Account's **System-Assigned Managed Identity** (`az login --identity`). No credentials or secrets are stored in the runbook.
2. **Extracts the Maintenance Configuration ID** from the Event Grid webhook payload (`WebhookData.RequestBody`). This identifies which maintenance configuration triggered the event.
3. **Queries Azure Resource Graph** (KQL) across all subscriptions to find every VM assigned to that maintenance configuration.
4. **Checks each VM's power state** — if a VM is deallocated, it starts it (`az vm start --no-wait`) and tags it with `StartedByPreMaintenance = true`.
5. VMs that are already running are skipped.

The tag is the handoff mechanism between pre and post — it marks which VMs the script started so the post-maintenance runbook knows which ones to shut back down.

### Post-Maintenance Runbook (`rn-lirook-postMaintenance`)

After patching completes, Event Grid fires the post-maintenance webhook. This runbook:

1. **Authenticates** with Managed Identity the same way.
2. **Queries Azure Resource Graph** with the same KQL query to find assigned VMs.
3. **Checks each VM for the `StartedByPreMaintenance` tag** — if present, it deallocates the VM (`az vm deallocate --no-wait`) and removes the tag.
4. VMs without the tag (i.e., VMs that were already running before maintenance) are left untouched.

### Authentication & Permissions

Both runbooks use the Automation Account's **System-Assigned Managed Identity** to authenticate. No passwords, service principal secrets, or certificates are involved. The identity is assigned two roles at the **tenant root management group** level:

- **Reader** — allows the runbooks to query Azure Resource Graph and read VM instance views across all subscriptions.
- **Virtual Machine Contributor** — allows starting and deallocating VMs, and managing tags.

### Flow

```
Maintenance Window Triggers
        │
        ▼
Azure Update Manager starts patching VMs
        │
        ├── Pre-Maintenance Event ──► Event Grid ──► Webhook ──► Pre-Maintenance Runbook
        │                                                          • Login with Managed Identity
        │                                                          • Query Resource Graph for VMs
        │                                                          • Start deallocated VMs
        │                                                          • Tag them: StartedByPreMaintenance=true
        │
        │   (patches are applied to running VMs)
        │
        └── Post-Maintenance Event ─► Event Grid ──► Webhook ──► Post-Maintenance Runbook
                                                                   • Login with Managed Identity
                                                                   • Query Resource Graph for VMs
                                                                   • Deallocate tagged VMs
                                                                   • Remove the tag
```

## Prerequisites

Before deploying this solution:

- **Terraform state backend** — A storage account must exist for remote state (`rg-lirook-tfstate-prod` / `sttfstatelirookprod`).
- **Key Vault secrets** — Two secrets must be created in `kvlirook-prod-001` containing the Automation Account webhook URLs for pre and post maintenance. Webhook URLs are only available at creation time — retrieve them from Terraform state after initial apply and store them in Key Vault.
- **Role assignments** — The Automation Account's managed identity needs **Reader** and **Virtual Machine Contributor** at the tenant root management group so the runbooks can query Resource Graph and start/stop VMs across all subscriptions.
- **Azure Resource Graph CLI extension** — Installed automatically by the runbooks at runtime (`az extension add --name resource-graph`).
- **VM association** — VMs must be assigned to the appropriate maintenance configuration for patching to take effect. This is handled outside of this module.

## Project Structure

| File | Purpose |
|------|---------|
| `main.tf` | Provider configuration |
| `backend.tf` | Remote state backend |
| `variables.tf` | Input variable declarations |
| `terraform.tfvars` | Environment-specific values |
| `automation_account.tf` | Automation Account and webhooks |
| `runbooks.tf` | Pre and post maintenance runbooks |
| `maintenance.tf` | Four maintenance configuration schedules |
| `eventgrid.tf` | Event Grid system topic |
| `eventgrid_subscriptions.tf` | Event subscriptions routing to webhooks |
| `role_assignments.tf` | Managed identity role assignments |
| `data.tf` | Key Vault secret lookups for webhook URLs |
| `scripts/` | PowerShell runbook source files |
| `archives/import.ps1` | One-time import script for existing resources |
