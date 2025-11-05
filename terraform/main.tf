terraform {
  required_version = ">= 1.0"

  required_providers {
    sakuracloud = {
      source  = "sacloud/sakuracloud"
      version = "~> 2.25"
    }
  }
}

provider "sakuracloud" {
  token  = var.sakura_token
  secret = var.sakura_secret
  zone   = var.zone
}
