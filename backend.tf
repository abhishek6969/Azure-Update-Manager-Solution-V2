

terraform {
  backend "azurerm" {

    resource_group_name  = "rg-lirook-tfstate-prod"
    storage_account_name = "sttfstatelirookprod"
    container_name       = "tf-state-um"
    key                  = "terraform.tfstate"
  }
}
