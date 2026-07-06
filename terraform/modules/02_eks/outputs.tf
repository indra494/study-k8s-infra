output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "oidc_provider_url" {
  value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_security_group_id" {
  # 관리형 노드그룹에 별도 SG를 지정하지 않으면 AWS가 자동 생성해서 붙이는
  # cluster shared SG (eks-cluster-sg-*) 가 실제 노드/파드에 적용되는 SG.
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}





