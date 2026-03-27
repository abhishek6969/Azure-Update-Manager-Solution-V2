#!/usr/bin/env pwsh
# =============================================================================
# Import existing Azure resources into Terraform state
# Run: terraform init first, then execute this script
# =============================================================================

$SUB    = "a1b2c3d4-e5f6-4a5b-8c7d-e9f0a1b2c3d4"
$RG     = "rg-lirook-updatemanagement"
$AA     = "aa-lirook-updatemanagement-dev"
$PREFIX = "/subscriptions/$SUB/resourceGroups/$RG"

# --- Automation Account ---
terraform import azurerm_automation_account.this "$PREFIX/providers/Microsoft.Automation/automationAccounts/$AA"

# --- Runbooks ---
terraform import azurerm_automation_runbook.post_maintenance "$PREFIX/providers/Microsoft.Automation/automationAccounts/$AA/runbooks/rn-lirook-postMaintenance"
terraform import azurerm_automation_runbook.pre_maintenance "$PREFIX/providers/Microsoft.Automation/automationAccounts/$AA/runbooks/rn-lirook-preMaintenance"

# --- Webhooks ---
terraform import azurerm_automation_webhook.post_maintenance "$PREFIX/providers/Microsoft.Automation/automationAccounts/$AA/webHooks/wh-postMaintenance"
terraform import azurerm_automation_webhook.pre_maintenance "$PREFIX/providers/Microsoft.Automation/automationAccounts/$AA/webHooks/wh-preMaintenance"

# --- Event Grid ---
terraform import azurerm_eventgrid_system_topic.maintenance "$PREFIX/providers/Microsoft.EventGrid/systemTopics/lirook-eg-topic"

# --- Maintenance Configurations ---
terraform import azurerm_maintenance_configuration.linux_nonprd "$PREFIX/providers/Microsoft.Maintenance/maintenanceConfigurations/mc-linux-nonprd"
terraform import azurerm_maintenance_configuration.linux_prd "$PREFIX/providers/Microsoft.Maintenance/maintenanceConfigurations/mc-linux-prd"
terraform import azurerm_maintenance_configuration.windows_nonprd "$PREFIX/providers/Microsoft.Maintenance/maintenanceConfigurations/mc-windows-nonprd"
terraform import azurerm_maintenance_configuration.windows_prd "$PREFIX/providers/Microsoft.Maintenance/maintenanceConfigurations/mc-windows-prd"


terraform import azurerm_eventgrid_system_topic_event_subscription.pre_maintenance "$PREFIX/providers/Microsoft.EventGrid/systemTopics/test/eventSubscriptions/es-pre-maintenance"

terraform import azurerm_eventgrid_system_topic_event_subscription.post_maintenance "$PREFIX/providers/Microsoft.EventGrid/systemTopics/test/eventSubscriptions/es-post-maintenance"