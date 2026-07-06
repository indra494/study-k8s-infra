# 1. 정책 생성
resource "aws_iam_policy" "lb_controller_policy" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/iam_policy.json") # 아래에 json 파일 생성 필요
}

# 2. OIDC Provider 가져오기 (이미 EKS에서 생성됨)
data "aws_iam_openid_connect_provider" "eks" {
  url = var.oidc_provider_url
}

# 3. IRSA를 위한 Role 생성 (신뢰 관계 설정)
resource "aws_iam_role" "lb_controller_role" {
  name = "eks-load-balancer-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

# 4. 정책 연결
resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.lb_controller_role.name
  policy_arn = aws_iam_policy.lb_controller_policy.arn
}