resource "azurerm_automation_account" "this" {
  name                          = var.automation_account_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku_name                      = "Basic"
  local_authentication_enabled  = true
  public_network_access_enabled = true
  tags                          = var.default_tags

  identity {
    type = "SystemAssigned"
  }
}

# Note: Webhook URIs are only available at creation time.
#       After initial apply, retrieve them from terraform state:
#         terraform state show azurerm_automation_webhook.post_maintenance
# 
#       Store the URIs securely (e.g. Key Vault) for use in Event Grid subscriptions.

resource "azurerm_automation_webhook" "post_maintenance" {
  name                    = "wh-postMaintenance"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  expiry_time             = "2027-03-23T08:11:09.74+00:00"
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.post_maintenance.name
}

resource "azurerm_automation_webhook" "pre_maintenance" {
  name                    = "wh-preMaintenance"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  expiry_time             = "2027-03-23T08:09:50.113+00:00"
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.pre_maintenance.name
}
