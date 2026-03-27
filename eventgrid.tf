resource "azurerm_eventgrid_system_topic" "maintenance" {
  location               = var.location
  name                   = "lirook-eg-topic"
  resource_group_name    = var.resource_group_name
  source_resource_id     = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/microsoft.maintenance/maintenanceConfigurations/mc-windows-nonprd"
  tags = merge(var.default_tags, {
    CreateDate = "2026-03-18"
  })
  topic_type = "Microsoft.Maintenance.MaintenanceConfigurations"
}
