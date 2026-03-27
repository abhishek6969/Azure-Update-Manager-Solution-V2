resource "azurerm_automation_runbook" "post_maintenance" {
  automation_account_name  = azurerm_automation_account.this.name
  content                  = file("${path.module}/scripts/rn-lirook-postMaintenance.ps1")
  description              = ""
  job_schedule             = []
  location                 = var.location
  log_activity_trace_level = 0
  log_progress             = false
  log_verbose              = false
  name                     = "rn-lirook-postMaintenance"
  resource_group_name      = var.resource_group_name
  runbook_type             = "PowerShell72"
  tags = merge(var.default_tags, {
    CreateDate = "2026-03-23"
  })
}

resource "azurerm_automation_runbook" "pre_maintenance" {
  automation_account_name  = azurerm_automation_account.this.name
  content                  = file("${path.module}/scripts/rn-lirook-preMaintenance.ps1")
  description              = ""
  job_schedule             = []
  location                 = var.location
  log_activity_trace_level = 0
  log_progress             = false
  log_verbose              = false
  name                     = "rn-lirook-preMaintenance"
  resource_group_name      = var.resource_group_name
  runbook_type             = "PowerShell72"
  tags = merge(var.default_tags, {
    CreateDate = "2026-03-23"
  })
}
