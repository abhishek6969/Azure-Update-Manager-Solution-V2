variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
}

variable "automation_account_name" {
  description = "Name of the automation account."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "default_tags" {
  description = "Default tags applied to resources."
  type        = map(string)
}

