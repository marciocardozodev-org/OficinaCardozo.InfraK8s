terraform {
  backend "s3" {
    bucket  = "oficina-cardozo-terraform-state-sp"
    key     = "eks/prod/terraform.tfstate"
    region  = "sa-east-1"
    encrypt = true
  }
}
