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

variable "enable_eks" {
  description = "Se true, cria o cluster EKS e recursos relacionados."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
  default     = "oficina-cardozo-eks"
}

variable "vpc_cidr" {
  description = "CIDR da VPC usada pelo EKS."
  type        = string
  default     = "10.1.0.0/16"
}

# VPC dedicada para o EKS (criada apenas quando enable_eks=true)
resource "aws_vpc" "eks" {
  count                = var.enable_eks ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "eks" {
  count  = var.enable_eks ? 1 : 0
  vpc_id = aws_vpc.eks[0].id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "public_1" {
  count                   = var.enable_eks ? 1 : 0
  vpc_id                  = aws_vpc.eks[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name                       = "${var.cluster_name}-public-1"
    "kubernetes.io/role/elb"  = "1"
  }
}

resource "aws_subnet" "public_2" {
  count                   = var.enable_eks ? 1 : 0
  vpc_id                  = aws_vpc.eks[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name                       = "${var.cluster_name}-public-2"
    "kubernetes.io/role/elb"  = "1"
  }
}

resource "aws_subnet" "private_1" {
  count             = var.enable_eks ? 1 : 0
  vpc_id            = aws_vpc.eks[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = "${var.aws_region}a"

  tags = {
    Name                              = "${var.cluster_name}-private-1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_2" {
  count             = var.enable_eks ? 1 : 0
  vpc_id            = aws_vpc.eks[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3)
  availability_zone = "${var.aws_region}b"

  tags = {
    Name                              = "${var.cluster_name}-private-2"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_route_table" "public" {
  count  = var.enable_eks ? 1 : 0
  vpc_id = aws_vpc.eks[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks[0].id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_1" {
  count          = var.enable_eks ? 1 : 0
  subnet_id      = aws_subnet.public_1[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "public_2" {
  count          = var.enable_eks ? 1 : 0
  subnet_id      = aws_subnet.public_2[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "eks_cluster" {
  count  = var.enable_eks ? 1 : 0
  name   = "${var.cluster_name}-cluster-sg"
  vpc_id = aws_vpc.eks[0].id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

resource "aws_iam_role" "eks_cluster" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSVPCResourceController" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_eks_cluster" "this" {
  count = var.enable_eks ? 1 : 0

  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    # Para simplificar o laboratório inicial, usamos subnets públicas.
    # Em produção, o ideal é manter o cluster em subnets privadas com NAT.
    subnet_ids         = [aws_subnet.public_1[0].id, aws_subnet.public_2[0].id]
    security_group_ids = [aws_security_group.eks_cluster[0].id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSVPCResourceController
  ]
}

resource "aws_iam_role" "eks_node" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_node_group" "default" {
  count = var.enable_eks ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.eks_node[0].arn
  # Para o primeiro cluster, colocamos os nodes em subnets públicas;
  # isso evita problemas de acesso ao endpoint da API do EKS sem NAT.
  subnet_ids      = [aws_subnet.public_1[0].id, aws_subnet.public_2[0].id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.small"]

  tags = {
    Name = "${var.cluster_name}-node-group-default"
  }
}
