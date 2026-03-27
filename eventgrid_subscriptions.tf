resource "azurerm_eventgrid_system_topic_event_subscription" "pre_maintenance" {
  name                = "es-pre-maintenance"
  system_topic        = azurerm_eventgrid_system_topic.maintenance.name
  resource_group_name = var.resource_group_name
  advanced_filtering_on_arrays_enabled = true

  webhook_endpoint {
    url                               = data.azurerm_key_vault_secret.webhook_pre_maintenance.value
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }
}

resource "azurerm_eventgrid_system_topic_event_subscription" "post_maintenance" {
  name                = "es-post-maintenance"
  system_topic        = azurerm_eventgrid_system_topic.maintenance.name
  resource_group_name = var.resource_group_name
  advanced_filtering_on_arrays_enabled = true

  webhook_endpoint {
    url                               = data.azurerm_key_vault_secret.webhook_post_maintenance.value
    max_events_per_batch = 1
    preferred_batch_size_in_kilobytes = 64
  }
}
