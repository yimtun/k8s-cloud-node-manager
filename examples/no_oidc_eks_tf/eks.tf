terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.90.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.27.0"
    }
  }
}

provider "aws" {
  #alias = "virginia"
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "eks_vpc" {
  #provider = aws.virginia
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name                                   = "eks-vpc"
    "kubernetes.io/cluster/my-eks-cluster" = "shared"
  }
}

#
resource "aws_subnet" "public" {
  #provider = aws.virginia
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name                                   = "eks-public-${count.index + 1}"
    "kubernetes.io/cluster/my-eks-cluster" = "shared"
    "kubernetes.io/role/elb"               = "1"
  }
}

#
resource "aws_subnet" "private" {
  #provider = aws.virginia
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                   = "eks-private-${count.index + 1}"
    "kubernetes.io/cluster/my-eks-cluster" = "shared"
    "kubernetes.io/role/internal-elb"      = "1"
  }
}

#
resource "aws_internet_gateway" "igw" {
  #provider = aws.virginia
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  }
}

#
resource "aws_eip" "nat" {
  #provider = aws.virginia
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  #provider = aws.virginia
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "eks-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

#
resource "aws_route_table" "public" {
  #provider = aws.virginia
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "eks-public-rt"
  }
}

resource "aws_route_table" "private" {
  #provider = aws.virginia
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "eks-private-rt"
  }
}

#
resource "aws_route_table_association" "public" {
  #provider = aws.virginia
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  #provider = aws.virginia

  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# EKS  IAM
resource "aws_iam_role" "eks_cluster" {
  #provider = aws.virginia
  name = "eks-cluster-role"

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

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

#
resource "aws_iam_role" "eks_node_group" {
  name = "eks-node-group-role"

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

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

#
resource "aws_eks_cluster" "main" {
  #provider = aws.virginia
  name     = "my-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.32"

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }



  access_config {
    #authentication_mode = "API_AND_CONFIG_MAP"  #
    authentication_mode = "API"  #
  }



  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}

#



resource "aws_eks_node_group" "main" {
  #provider = aws.virginia
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "main"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.micro"]



  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry
  ]
}

# EKS
resource "aws_security_group" "eks_cluster" {
  #provider = aws.virginia
  name        = "eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.eks_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-cluster-sg"
  }
}

#
data "aws_availability_zones" "available" {
  #provider = aws.virginia
  state = "available"
}

#  Kubernetes provider
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
  }
}

#
output "cluster_endpoint" {
  description = "EKS"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "EKS"
  value       = aws_eks_cluster.main.name
}

# output "cluster_certificate_authority_data" {
#   description = "EKS"
#   value       = aws_eks_cluster.main.certificate_authority[0].data
# }


################################################
#
data "aws_caller_identity" "current" {}

#
resource "aws_eks_access_entry" "admin" {
  #provider = aws.virginia
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_access_entry.admin,
  ]
}

#
resource "aws_eks_access_policy_association" "admin" {
  #provider = aws.virginia
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_access_entry.admin,
  ]
}


#
#
#

resource "aws_eks_access_entry" "root" {
  #provider = aws.virginia
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  type          = "STANDARD"
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_access_entry.admin,
  ]
}
#
resource "aws_eks_access_policy_association" "root" {
  #provider = aws.virginia
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_access_entry.admin,
  ]
}






#
resource "kubernetes_service_account" "app_service_account" {
  metadata {
    name      = "extended-api-server"
    namespace = "default"
  }
}

#  Kubernetes ClusterRole
resource "kubernetes_cluster_role" "app_cluster_role" {
  metadata {
    name = "basic-k8s-extension-api"
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get" ,"list"]
  }
}

# ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "app_cluster_role_binding" {
  metadata {
    name = "extended-api-server"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.app_cluster_role.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.app_service_account.metadata[0].name
    namespace = kubernetes_service_account.app_service_account.metadata[0].namespace
  }
}


# aws eks update-kubeconfig --name my-eks-cluster --region us-east-1 --kubeconfig ./config-eks

# use kubeconfig
# export  KUBECONFIG=./config-eks
# kubectl get node



## delete eks
# terraform destroy -target=aws_eks_node_group.main
# terraform destroy -target=aws_eks_cluster.main
# terraform destroy

