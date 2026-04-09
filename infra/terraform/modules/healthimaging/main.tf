terraform {
  required_providers {
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.0"
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.env}"
}

resource "awscc_healthimaging_datastore" "this" {
  datastore_name = "${local.name_prefix}-dicom"

  tags = {
    Project     = var.project
    Environment = var.env
  }
}
