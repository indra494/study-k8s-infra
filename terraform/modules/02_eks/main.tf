resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  # 변수 대신 바로 IAM 리소스를 참조합니다
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = var.subnet_ids
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }

  # 콘솔의 Resources 탭(Access Entry 방식) 지원 - 기존 aws-auth ConfigMap 방식도 그대로 유지
  # bootstrap_cluster_creator_admin_permissions을 명시 안 하면 null로 인식되어
  # 기존 값(true)과 달라서 클러스터 전체 재생성(destroy)이 걸리니 반드시 명시해야 함
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}