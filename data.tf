data "azurerm_key_vault_secret" "webhook_pre_maintenance" {
  name         = "webhook-url-pre-maintenance"
  key_vault_id = "/subscriptions/a1b2c3d4-e5f6-4a5b-8c7d-e9f0a1b2c3d4/resourceGroups/rg-lirook-sharedservices-prod-001/providers/Microsoft.KeyVault/vaults/kvlirook-prod-001"
}

data "azurerm_key_vault_secret" "webhook_post_maintenance" {
  name         = "webhook-url-post-maintenance"
  key_vault_id = "/subscriptions/a1b2c3d4-e5f6-4a5b-8c7d-e9f0a1b2c3d4/resourceGroups/rg-lirook-sharedservices-prod-001/providers/Microsoft.KeyVault/vaults/kvlirook-prod-001"
}
