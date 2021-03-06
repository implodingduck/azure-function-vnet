terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.83.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.1.0"
    }
  }
  backend "azurerm" {

  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}

locals {
  func_name = "funcvnet${random_string.unique.result}"
  loc_for_naming = lower(replace(var.location, " ", ""))
  tags = {
    "managed_by" = "terraform"
    "repo"       = "azure-function-vnet"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.func_name}-${local.loc_for_naming}"
  location = var.location
}

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}


data "azurerm_client_config" "current" {}

data "azurerm_log_analytics_workspace" "default" {
  name                = "DefaultWorkspace-${data.azurerm_client_config.current.subscription_id}-EUS"
  resource_group_name = "DefaultResourceGroup-EUS"
} 

data "azurerm_network_security_group" "basic" {
    name                = "basic"
    resource_group_name = "rg-network-eastus"
}


resource "azurerm_virtual_network" "default" {
  name                = "vnet-${local.func_name}-${local.loc_for_naming}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.4.0.0/24"]

  tags = local.tags
}

resource "azurerm_subnet" "pe" {
  name                  = "snet-privateendpoints-${local.loc_for_naming}"
  resource_group_name   = azurerm_virtual_network.default.resource_group_name
  virtual_network_name  = azurerm_virtual_network.default.name
  address_prefixes      = ["10.4.0.0/26"]

  enforce_private_link_endpoint_network_policies = true

}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = data.azurerm_network_security_group.basic.id
}

resource "azurerm_subnet" "functions" {
  name                  = "snet-functions-${local.loc_for_naming}"
  resource_group_name   = azurerm_virtual_network.default.resource_group_name
  virtual_network_name  = azurerm_virtual_network.default.name
  address_prefixes      = ["10.4.0.64/26"]
  service_endpoints = [
    "Microsoft.Web",
    "Microsoft.Storage"
  ]
  delegation {
    name = "serverfarm-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
 
}

resource "azurerm_subnet_network_security_group_association" "functions" {
  subnet_id                 = azurerm_subnet.functions.id
  network_security_group_id = data.azurerm_network_security_group.basic.id
}

resource "azurerm_subnet" "functions2" {
  name                  = "snet-functions2-${local.loc_for_naming}"
  resource_group_name   = azurerm_virtual_network.default.resource_group_name
  virtual_network_name  = azurerm_virtual_network.default.name
  address_prefixes      = ["10.4.0.128/26"]
  delegation {
    name = "serverfarm-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
  service_endpoints = [
    "Microsoft.Web",
    "Microsoft.Storage"
  ]
 
}

resource "azurerm_subnet_network_security_group_association" "functions2" {
  subnet_id                 = azurerm_subnet.functions2.id
  network_security_group_id = data.azurerm_network_security_group.basic.id
}


resource "azurerm_private_dns_zone" "blob" {
  name                      = "privatelink.blob.core.windows.net"
  resource_group_name       = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.default.id
}

resource "azurerm_private_dns_zone" "functions" {
  name                      = "privatelink.azurewebsites.net"
  resource_group_name       = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "functions" {
  name                  = "functions"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.functions.name
  virtual_network_id    = azurerm_virtual_network.default.id
}

resource "azurerm_private_endpoint" "pe" {
  name                = "pe-sa${local.func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id

  private_service_connection {
    name                           = "pe-connection-sa${local.func_name}"
    private_connection_resource_id = azurerm_storage_account.sa.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
  private_dns_zone_group {
    name                 = azurerm_private_dns_zone.blob.name
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_private_endpoint" "pefunction" {
  depends_on = [
    null_resource.publish_func2
  ]
  name                = "pe-${local.func_name}priv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id

  private_service_connection {
    name                           = "pe-connection-${local.func_name}priv"
    private_connection_resource_id = azurerm_function_app.func2.id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }
  private_dns_zone_group {
    name                 = azurerm_private_dns_zone.functions.name
    private_dns_zone_ids = [azurerm_private_dns_zone.functions.id]
  }
}


resource "azurerm_storage_account" "sa" {
  name                     = "sa${local.func_name}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.tags
}

resource "azurerm_storage_account_network_rules" "fw" {
  depends_on = [
    azurerm_app_service_virtual_network_swift_connection.example,
    azurerm_app_service_virtual_network_swift_connection.example2,
    null_resource.publish_func,
    null_resource.publish_func2 
  ]
  storage_account_id = azurerm_storage_account.sa.id

  default_action             = "Deny"

  virtual_network_subnet_ids = [
    azurerm_subnet.functions.id, 
    azurerm_subnet.functions2.id
  ]

  ip_rules                   = [
    "20.37.158.0/23",
    "20.37.194.0/24",
    "20.39.13.0/26",
    "20.41.6.0/23",
    "20.41.194.0/24",
    "20.42.5.0/24",
    "20.42.134.0/23",
    "20.42.226.0/24",
    "20.45.196.64/26",
    "20.189.107.0/24",
    "20.195.68.0/24",
    "40.74.28.0/23",
    "40.80.187.0/24",
    "40.82.252.0/24",
    "40.119.10.0/24",
    "51.104.26.0/24",
    "52.150.138.0/24",
    "52.228.82.0/24",
    "191.235.226.0/24"
  ]

  bypass = [
    "AzureServices"
  ]
}

resource "azurerm_app_service_plan" "asp" {
  name                = "asp-${local.func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "elastic"
  reserved = true
  sku {
    tier = "ElasticPremium"
    size = "EP1"
  }
}

resource "azurerm_app_service_plan" "asp2" {
  name                = "asp-${local.func_name}-2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "elastic"
  reserved = true
  sku {
    tier = "ElasticPremium"
    size = "EP1"
  }
}

resource "azurerm_application_insights" "app" {
  name                = "${local.func_name}-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"
  workspace_id = data.azurerm_log_analytics_workspace.default.id
}

resource "azurerm_application_insights" "app2" {
  name                = "${local.func_name}-2-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"
  workspace_id = data.azurerm_log_analytics_workspace.default.id
}
resource "azurerm_function_app" "func" {
  name                       = "${local.func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.asp.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  version = "~4"
  os_type = "linux"
  https_only = true
  site_config {
    linux_fx_version = "node|14"
    use_32_bit_worker_process = false
    vnet_route_all_enabled    = true
  }
  app_settings = {
      "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app.instrumentation_key
      "FUNCTIONS_WORKER_RUNTIME"       = "node"
      "WEBSITE_NODE_DEFAULT_VERSION"   = "~14"
      "WEBSITE_CONTENTOVERVNET"        = "1"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_app_service_virtual_network_swift_connection" "example" {
  app_service_id = azurerm_function_app.func.id
  subnet_id      = azurerm_subnet.functions.id
}


resource "local_file" "localsettings" {
    content     = <<-EOT
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "AzureWebJobsStorage": ""
  }
}
EOT
    filename = "../func1/local.settings.json"
}

resource "null_resource" "publish_func"{
  depends_on = [
    azurerm_function_app.func,
    local_file.localsettings
  ]
  triggers = {
    index = "${timestamp()}"
  }
  provisioner "local-exec" {
    working_dir = "../func1"
    command     = "func azure functionapp publish ${azurerm_function_app.func.name} --build remote"
  }
}

resource "azurerm_function_app" "func2" {
  name                       = "${local.func_name}priv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.asp2.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  version = "~4"
  os_type = "linux"
  https_only = true
  site_config {
    linux_fx_version = "node|14"
    use_32_bit_worker_process = false
    vnet_route_all_enabled    = true
  }

  app_settings = {
      "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app2.instrumentation_key
      "FUNCTIONS_WORKER_RUNTIME"       = "node"
      "WEBSITE_NODE_DEFAULT_VERSION"   = "~14"
      "WEBSITE_CONTENTOVERVNET"        = "1"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_app_service_virtual_network_swift_connection" "example2" {
  app_service_id = azurerm_function_app.func2.id
  subnet_id      = azurerm_subnet.functions2.id
}


resource "local_file" "localsettings2" {
    content     = <<-EOT
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "AzureWebJobsStorage": ""
  }
}
EOT
    filename = "../func2/local.settings.json"
}

resource "null_resource" "publish_func2"{
  depends_on = [
    azurerm_function_app.func2,
    local_file.localsettings2
  ]
  triggers = {
    index = "1"
  }
  provisioner "local-exec" {
    working_dir = "../func2"
    command     = "func azure functionapp publish ${azurerm_function_app.func2.name} --build remote"
  }
}

