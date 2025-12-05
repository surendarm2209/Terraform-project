provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "kubernetes_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "kubernetes-vpc"
  }
}

resource "aws_subnet" "kubernetes_subnet" {
  count = 2
  vpc_id                  = aws_vpc.kubernetes_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.kubernetes_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "kubernetes-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "kubernetes_igw" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  tags = {
    Name = "kubernetes-igw"
  }
}

resource "aws_route_table" "kubernetes_route_table" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubernetes_igw.id
  }

  tags = {
    Name = "kubernetes-route-table"
  }
}

resource "aws_route_table_association" "kubernetes_association" {
  count          = 2
  subnet_id      = aws_subnet.kubernetes_subnet[count.index].id
  route_table_id = aws_route_table.kubernetes_route_table.id
}

resource "aws_security_group" "kubernetes_cluster_sg" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubernetes-cluster-sg"
  }
}

resource "aws_security_group" "kubernetes_node_sg" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubernetes-node-sg"
  }
}

resource "aws_iam_role" "kubernetes_cluster_role" {
  name = "kubernetes-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "kubernetes_cluster_role_policy" {
  role       = aws_iam_role.kubernetes_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "kubernetes" {
  name     = "kubernetes-cluster"
  role_arn = aws_iam_role.kubernetes_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.kubernetes_subnet[*].id
    security_group_ids = [aws_security_group.kubernetes_cluster_sg.id]
  }
}

# -----------------------------------------------------------
# 🚨 NEW REQUIRED RESOURCE: OIDC provider for IRSA
# -----------------------------------------------------------
resource "aws_iam_openid_connect_provider" "kubernetes" {
  url             = aws_eks_cluster.kubernetes.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0ecd032a"]
}

# -----------------------------------------------------------
# Addon (with correct ordering)
# -----------------------------------------------------------
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.kubernetes.name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.kubernetes,
    aws_iam_openid_connect_provider.kubernetes
  ]
}

resource "aws_iam_role" "kubernetes_node_group_role" {
  name = "kubernetes-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "kubernetes_node_group_role_policy" {
  role       = aws_iam_role.kubernetes_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "kubernetes_node_group_cni_policy" {
  role       = aws_iam_role.kubernetes_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_P_
