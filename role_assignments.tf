resource "azurerm_role_assignment" "reader" {
  scope                = "/providers/Microsoft.Management/managementGroups/d79555d1-8adb-46ea-af6c-b6b2a24e4fe7"
  role_definition_name = "Reader"
  principal_id         = azurerm_automation_account.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "vm_contributor" {
  scope                = "/providers/Microsoft.Management/managementGroups/d79555d1-8adb-46ea-af6c-b6b2a24e4fe7"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.this.identity[0].principal_id
}
