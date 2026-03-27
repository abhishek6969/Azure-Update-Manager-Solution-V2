resource "azurerm_maintenance_configuration" "linux_nonprd" {
  in_guest_user_patch_mode = "User"
  location                 = var.location
  name                     = "mc-linux-nonprd"
  properties               = {}
  resource_group_name      = var.resource_group_name
  scope                    = "InGuestPatch"
  tags = merge(var.default_tags, {
    CreateDate = "2026-03-10"
  })
  visibility = "Custom"

  install_patches {
    reboot = "IfRequired"

    linux {
      classifications_to_include    = ["Critical", "Security"]
      package_names_mask_to_exclude = []
      package_names_mask_to_include = []
    }

    windows {
      classifications_to_include = ["Critical", "Security"]
      kb_numbers_to_exclude      = []
      kb_numbers_to_include      = []
    }
  }

  window {
    duration             = "03:55"
    expiration_date_time = ""
    recur_every          = "1Week Monday,Wednesday,Friday"
    start_date_time      = "2026-03-11 06:00"
    time_zone            = "W. Europe Standard Time"
  }
}

resource "azurerm_maintenance_configuration" "linux_prd" {
  in_guest_user_patch_mode = "User"
  location                 = var.location
  name                     = "mc-linux-prd"
  properties               = {}
  resource_group_name      = var.resource_group_name
  scope                    = "InGuestPatch"
  tags = merge(var.default_tags, {
    CreateDate = "2026-03-10"
  })
  visibility = "Custom"

  install_patches {
    reboot = "IfRequired"

    linux {
      classifications_to_include    = ["Critical", "Security"]
      package_names_mask_to_exclude = []
      package_names_mask_to_include = []
    }

    windows {
      classifications_to_include = ["Critical", "Security"]
      kb_numbers_to_exclude      = []
      kb_numbers_to_include      = []
    }
  }

  window {
    duration             = "03:55"
    expiration_date_time = ""
    recur_every          = "1Week Monday,Wednesday,Friday"
    start_date_time      = "2026-03-11 06:00"
    time_zone            = "W. Europe Standard Time"
  }
}

resource "azurerm_maintenance_configuration" "windows_nonprd" {
  in_guest_user_patch_mode = "User"
  location                 = var.location
  name                     = "mc-windows-nonprd"
  properties               = {}
  resource_group_name      = var.resource_group_name
  scope                    = "InGuestPatch"
  tags = merge(var.default_tags, {
    CreateDate = "2026-03-10"
  })
  visibility = "Custom"

  install_patches {
    reboot = "IfRequired"

    linux {
      classifications_to_include    = ["Critical", "Security"]
      package_names_mask_to_exclude = []
      package_names_mask_to_include = []
    }

    windows {
      classifications_to_include = ["Critical", "Security"]
      kb_numbers_to_exclude      = []
      kb_numbers_to_include      = []
    }
  }

  window {
    duration             = "03:55"
    expiration_date_time = ""
    recur_every          = "1Week Friday,Thursday"
    start_date_time      = "2026-03-26 06:00"
    time_zone            = "W. Europe Standard Time"
  }
}

resource "azurerm_maintenance_configuration" "windows_prd" {
  in_guest_user_patch_mode = "User"
  location                 = var.location
  name                     = "mc-windows-prd"
  properties               = {}
  resource_group_name      = var.resource_group_name
  scope                    = "InGuestPatch"
  tags = merge(var.default_tags, {
    CreateDate = "2026-03-10"
  })
  visibility = "Custom"

  install_patches {
    reboot = "IfRequired"

    linux {
      classifications_to_include    = ["Critical", "Security"]
      package_names_mask_to_exclude = []
      package_names_mask_to_include = []
    }

    windows {
      classifications_to_include = ["Critical", "Security"]
      kb_numbers_to_exclude      = []
      kb_numbers_to_include      = []
    }
  }

  window {
    duration             = "03:55"
    expiration_date_time = ""
    recur_every          = "1Week Friday"
    start_date_time      = "2026-03-17 06:00"
    time_zone            = "W. Europe Standard Time"
  }
}
