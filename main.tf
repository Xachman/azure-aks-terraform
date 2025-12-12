locals {
  cluster_name = "test"
}

data "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
}

resource "random_pet" "azurerm_kubernetes_cluster_name" {
  prefix = "cluster"
}

resource "random_pet" "azurerm_kubernetes_cluster_dns_prefix" {
  prefix = "dns"
}

resource "azurerm_kubernetes_cluster" "k8s" {
  location            = data.azurerm_resource_group.rg.location
  name                = local.cluster_name
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = random_pet.azurerm_kubernetes_cluster_dns_prefix.id

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name       = "agentpool"
    vm_size    = "Standard_D2s_v3"
    auto_scaling_enabled = true
    min_count = 1
    max_count = 3
    zones = []
  }
  linux_profile {
    admin_username = var.username

    ssh_key {
      key_data = azapi_resource_action.ssh_public_key_gen.output.publicKey
    }
  }
  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }
}


resource "azurerm_monitor_action_group" "cluster" {
  name                = "cluster-${local.cluster_name}"
  resource_group_name = var.resource_group_name
  short_name = "cluster-${local.cluster_name}"
}

resource "azurerm_monitor_workspace" "cluster" {
  name                = "cluster-${local.cluster_name}"
  resource_group_name = var.resource_group_name
  location            = data.azurerm_resource_group.rg.location
}

resource "azurerm_monitor_alert_prometheus_rule_group" "example" {
  name                = "cluster-${local.cluster_name}"
  location            = "West Europe"
  resource_group_name = var.resource_group_name
  cluster_name        = local.cluster_name
  rule_group_enabled  = false
  interval            = "PT1M"
  scopes              = [azurerm_monitor_workspace.cluster.id]
  rule {
    enabled    = false
    expression = <<EOF
histogram_quantile(0.99, sum(rate(jobs_duration_seconds_bucket{service="billing-processing"}[5m])) by (job_type))
EOF
    record     = "job_type:billing_jobs_duration_seconds:99p5m"
    labels = {
      team = "prod"
    }
  }

  rule {
    alert      = "Billing_Processing_Very_Slow"
    enabled    = true
    expression = <<EOF
histogram_quantile(0.99, sum(rate(jobs_duration_seconds_bucket{service="billing-processing"}[5m])) by (job_type))
EOF
    for        = "PT5M"
    severity   = 2

    action {
      action_group_id = azurerm_monitor_action_group.cluster.id
    }

    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT10M"
    }

    annotations = {
      annotationName = "annotationValue"
    }

    labels = {
      team = "prod"
    }
  }
  tags = {
    key = "value"
  }
}