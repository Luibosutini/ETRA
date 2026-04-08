locals {
  name_prefix = "${var.project}-${var.env}"
}

resource "aws_healthimaging_datastore" "this" {
  datastore_name = "${local.name_prefix}-dicom"

  tags = {
    Project     = var.project
    Environment = var.env
  }
}
