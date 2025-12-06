output "cluster_name" {
  value = aws_eks_cluster.devopsshack.name
}

output "node_group_name" {
  value = aws_eks_node_group.devopsshack.node_group_name
}

output "vpc_id" {
  value = aws_vpc.devopsshack_vpc.id
}
