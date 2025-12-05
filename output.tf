output "cluster_id" {
  value = aws_eks_cluster.kubernetes.id
}

output "node_group_id" {
  value = aws_eks_node_group.kubernetes.id
}


output "vpc_id" {
  value = aws_vpc.kubernetes_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.kubernetes_subnet[*].id
}
