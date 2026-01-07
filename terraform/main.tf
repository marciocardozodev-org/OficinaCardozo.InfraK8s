terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# TODO: adicionar aqui os recursos de Kubernetes (EKS, namespaces, ingress etc.)

# Marker: alteração mínima para testar fluxo de CI/CD (não afeta recursos)
