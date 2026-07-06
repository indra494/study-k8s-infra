# 인프라/CI-CD 상세 설정 문서

이 문서는 `study-k8s-infra`(로컬 경로: `workspace_09/infra`) 저장소를 중심으로, 지금까지 어떤 순서로 무엇을 설정했는지, 각 설정값이 정확히 무엇을 의미하는지, 그리고 아직 남아있는 작업이 무엇인지를 처음 보는 사람도 그대로 따라할 수 있는 수준으로 정리한 문서입니다.

관련 저장소 3개:
- `study-k8s-infra` (이 저장소, 로컬 `workspace_09/infra`) — Terraform 인프라 코드 + GitOps 매니페스트
- `study-k8s-engame-api` (로컬 `workspace_09/engame_api`) — Spring Boot 백엔드
- `study-k8s-engame-front` (로컬 `workspace_09/engame_front`) — React 프론트엔드 (Vite + Nginx)

기본 정보:
- AWS 계정 ID: `xxx`
- 리전: `ap-northeast-2` (서울)
- GitHub org/user: `xxxx`
- 환경: 현재 `dev`,`prod`

전체 큰 그림(다이어그램, 흐름 설명)은 [`ARCHITECTURE_PIPELINE.md`](ARCHITECTURE_PIPELINE.md)를 참고하세요. 이 문서는 "어떻게 하나하나 설정했는가"에 집중합니다.

---

## 목차

1. [Terraform 백엔드 부트스트랩](#1단계-terraform-백엔드-부트스트랩)
2. [VPC](#2단계-vpc)
3. [EKS 클러스터](#3단계-eks-클러스터)
4. [EKS 워커 노드 그룹](#4단계-eks-워커-노드-그룹)
5. [AWS Load Balancer Controller](#5단계-aws-load-balancer-controller)
6. [RDS (MySQL)](#6단계-rds-mysql)
7. [Bastion (SSM)](#7단계-bastion-ssm)
8. [ECR](#8단계-ecr)
9. [ArgoCD 설치 + GitOps 매니페스트](#9단계-argocd-설치--gitops-매니페스트)
10. [GitHub OIDC (CI/CD용 IAM)](#10단계-github-oidc-cicd용-iam)
11. [CI/CD 파이프라인 설계 (Black Duck → Trivy)](#11단계-cicd-파이프라인-설계-black-duck--trivy)
12. [파이프라인 실전 검증](#12단계-파이프라인-실전-검증)
13. [현재 남아있는 작업 / 확인 필요 항목](#13-현재-남아있는-작업--확인-필요-항목)

---

## 1단계: Terraform 백엔드 부트스트랩

**목적**: Terraform state 파일을 안전하게 저장하고, 여러 사람/여러 실행이 동시에 apply할 때 충돌 안 나게 잠그는 인프라를 제일 먼저 만듦.

**파일 위치**: `bootstrap/main.tf`

**구성**:
| 리소스 | 이름 | 설정 |
|---|---|---|
| S3 버킷 | `usb-terraform-state-2026` | 버전관리(versioning) 활성화, `prevent_destroy = true`로 실수 삭제 방지 |
| DynamoDB 테이블 | `terraform-lock` | `PAY_PER_REQUEST`, hash key `LockID` — terragrunt가 apply 시 이 테이블에 lock을 걺 |

**재현 방법** (이미 돼있어서 다시 할 필요 없음, 참고용):
```bash
cd bootstrap
terraform init
terraform apply
```

**상태**: ✅ 완료. 이후 모든 `terraform/live/dev/*` 모듈이 이 S3 버킷/DynamoDB를 공용 백엔드로 사용함 (`terraform/terragrunt.hcl`의 `remote_state` 블록).

---

## 2단계: VPC

**파일 위치**: `terraform/modules/01_vpc/`, `terraform/live/dev/01_vpc/terragrunt.hcl`

**핵심 설정값**:
| 항목 | 값 |
|---|---|
| VPC 이름 | `usb-dev-vpc` (`{project_name}-{env}-vpc` 패턴) |
| CIDR | `10.0.0.0/16` |
| 가용영역(AZ) | `ap-northeast-2a`, `ap-northeast-2c` (2개 AZ로 이중화) |
| Private subnet | `10.0.1.0/24`, `10.0.2.0/24` (EKS 노드, RDS, Bastion이 여기 위치) |
| Public subnet | `10.0.101.0/24`, `10.0.102.0/24` (ALB가 여기 위치) |

**재현 방법**:
```bash
cd terraform/live/dev/01_vpc
terragrunt plan
terragrunt apply
```

**상태**: ✅ 완료.

**주의점**: `project_name`(`usb`)은 루트 `terraform/terragrunt.hcl`의 `inputs`에서, `env`(`dev`)는 `terraform/live/dev/env.hcl`에서 가져와 조합함. 나중에 `live/prod`를 만들 때는 `env.hcl`만 `env = "prod"`로 바꾼 디렉토리를 복제하면 됨.

---

## 3단계: EKS 클러스터

**파일 위치**: `terraform/modules/02_eks/`, `terraform/live/dev/02_eks/terragrunt.hcl`

**핵심 설정값**:
| 항목 | 값 |
|---|---|
| 클러스터 이름 | `usb-dev-eks` |
| Subnet | VPC 모듈의 `private_subnets` output을 `dependency` 블록으로 자동 참조 |
| 인증 모드 | `API_AND_CONFIG_MAP` (콘솔 Access Entry 방식 + 기존 aws-auth ConfigMap 방식 둘 다 지원) |
| `bootstrap_cluster_creator_admin_permissions` | `true` — **반드시 명시해야 함**. 명시 안 하면 terraform이 null로 인식해서 기존 값(true)과 달라져 클러스터 전체가 재생성(destroy) 걸림 (코드 주석에 명시된 실제 겪은 이슈) |
| OIDC Provider | `terraform/modules/02_eks/oidc.tf`에서 `aws_iam_openid_connect_provider` 생성 — EKS 클러스터 자체의 OIDC(이건 **파드가 AWS 리소스에 접근할 때 쓰는 IRSA용** OIDC이고, 10단계의 GitHub Actions OIDC와는 별개) |

**의존관계**: `dependency "vpc"` — VPC가 먼저 apply돼 있어야 함 (terragrunt가 자동으로 순서 관리)

**재현 방법**:
```bash
cd terraform/live/dev/02_eks
terragrunt plan
terragrunt apply
```

**상태**: ✅ 완료.

**주의점**: 이 EKS의 OIDC Provider는 5단계(LB Controller)의 IRSA 인증에 쓰이는 것이고, 10단계 GitHub Actions OIDC(CI/CD용)와는 완전히 다른 자원입니다. 이름이 비슷해서 헷갈리기 쉬우니 구분해서 기억할 것.

---

## 4단계: EKS 워커 노드 그룹

**파일 위치**: `terraform/modules/03_eks_nodes/`, `terraform/live/dev/03_eks_nodes/terragrunt.hcl`

**핵심 설정값**:
| 항목 | 값 |
|---|---|
| 인스턴스 타입 | `t3.medium` |
| Scaling | desired 2 / min 1 / max 3 |
| 배치 | VPC private subnet |

**의존관계**: VPC + EKS 클러스터 둘 다 필요

**상태**: ✅ 완료. 현재 `kubectl get pods -n engame-dev`로 확인했을 때 파드가 정상적으로 스케줄링/실행 중.

---

## 5단계: AWS Load Balancer Controller

**파일 위치**: `terraform/modules/04_eks_lb_controller/` (IAM 정책/역할만 Terraform으로 관리), 실제 컨트롤러 설치는 **Helm**으로 진행

**핵심 설정값**:
- IAM 정책: `AWSLoadBalancerControllerIAMPolicy` (`iam_policy.json` 파일 필요 — AWS 공식 정책 문서 그대로 사용)
- IRSA Role: `eks-load-balancer-controller-role`, trust policy 조건은 `system:serviceaccount:kube-system:aws-load-balancer-controller` — 이 서비스어카운트로 파드가 뜰 때만 이 Role을 assume할 수 있음
- Helm 릴리즈 확인됨: `aws-load-balancer-controller` in `kube-system`, revision 2, chart `aws-load-balancer-controller-3.4.0`

**재현 방법 (Terraform 부분)**:
```bash
cd terraform/live/dev/04_eks_lb_controller
terragrunt apply
```

**재현 방법 (Helm 부분 — 이 저장소에 코드화돼 있지 않음, 수동 실행 필요)**:
```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=usb-dev-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller
```

**상태**: ✅ 완료(런타임 확인됨). ⚠️ **Helm install 명령 자체는 Terraform/코드로 관리되지 않고 있음** — 13번 항목 참고.

---

## 6단계: RDS (MySQL)

**파일 위치**: `terraform/modules/05_rds/`, `terraform/live/dev/05_rds/terragrunt.hcl`

**핵심 설정값**:
| 항목 | 값 |
|---|---|
| 엔진 | MySQL 8.0 |
| 인스턴스 클래스 | `db.t3.micro` |
| DB 이름 | `usb_db` |
| 사용자명 | `admin` |
| 비밀번호 | `random_password` 리소스로 자동 생성 (20자, 특수문자 없음) |
| 접근 제어 | `eks_node_sg_id`를 받아서 EKS 노드 → RDS 인바운드 허용 (보안그룹 참조) |
| `skip_final_snapshot` | `true` (dev 환경이라 삭제 시 스냅샷 안 남김 — **prod에서는 반드시 false로 바꿔야 함**) |

**비밀번호 보관**: `terraform/modules/05_rds/secrets.tf`에서 AWS Secrets Manager(`{name}-credentials`)에 `username/password/host/port/dbname`을 JSON으로 저장. 이 Secrets Manager 값이 실제로는 K8s Secret(`engame-db-credentials`)으로 별도 동기화되어 `gitops/base/api-deployment.yaml`의 `DB_PASSWORD` 환경변수가 여기서 값을 읽어옴 (`secretKeyRef`).

**재현 방법**:
```bash
cd terraform/live/dev/05_rds
terragrunt apply
```

**상태**: ✅ 완료.

**주의점**: RDS는 private subnet에 있어서 로컬 PC에서 직접 접속 불가. 7단계 Bastion을 통한 SSM 터널링으로만 접속 가능.

---

## 7단계: Bastion (SSM)

**파일 위치**: `terraform/modules/06_bastion/`, `terraform/live/dev/06_bastion/terragrunt.hcl`

**설계 포인트**: 전통적인 SSH bastion이 아니라 **SSM Session Manager 전용 bastion**입니다.
- 보안그룹(`terraform/modules/06_bastion/security.tf`): **인바운드 포트가 전혀 없음** (`egress`만 `0.0.0.0/0`으로 열림). 즉 22번 포트(SSH)조차 안 열려있음.
- IAM Role에 `AmazonSSMManagedInstanceCore` 정책만 붙어있어서, AWS SSM 서비스를 통해서만 세션 연결 가능 (`aws ssm start-session`)
- Bastion SG → RDS SG로 3306 포트 인바운드를 허용하는 `aws_security_group_rule`이 별도로 있어서, bastion에서 RDS로 접속 가능

**로컬에서 DB 접속하는 법 (DBeaver 등 GUI 툴 사용 시)**:
```bash
aws ssm start-session \
  --target <bastion-instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["usb-dev-rds.c3ukkso4igfj.ap-northeast-2.rds.amazonaws.com"],"portNumber":["3306"],"localPortNumber":["3306"]}'
```
터널이 열린 상태로 DBeaver에서 `localhost:3306`으로 접속하면 됨.

**상태**: ✅ 완료.

---

## 8단계: ECR

**파일 위치**: `terraform/modules/07_ecr/`, `terraform/live/dev/07_ecr/terragrunt.hcl`

**핵심 설정값**:
| 항목 | 값 |
|---|---|
| 리포지토리 | `usb-dev-engame-api`, `usb-dev-engame-front` (`for_each`로 2개 동시 생성) |
| `image_tag_mutability` | `MUTABLE` |
| `scan_on_push` | `true` — **ECR 자체에도 내장 취약점 스캔 기능이 켜져 있음** (Trivy와는 별개, 13번 항목 참고) |
| Lifecycle policy | 각 리포지토리별로 최근 10개 이미지만 남기고 자동 만료 |

**상태**: ✅ 완료.

---

## 9단계: ArgoCD 설치 + GitOps 매니페스트

**ArgoCD 설치**: Terraform/Helm 코드로 관리되지 않고, `argocd` 네임스페이스에 공식 설치 매니페스트(`kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml` 형태로 추정)를 직접 적용해서 설치된 상태입니다. 현재 실행 확인된 컴포넌트:
```
argocd-application-controller-0
argocd-applicationset-controller  (⚠️ 에러 상태, 13번 항목 참고)
argocd-dex-server
argocd-notifications-controller
argocd-redis
argocd-repo-server
argocd-server
```
이미지 버전: `quay.io/argoproj/argocd:v3.4.4`

**GitOps 매니페스트 구조** (`gitops/` 디렉토리):
```
gitops/
├── argocd/
│   └── engame-dev-application.yaml   # ArgoCD Application 정의 (아래 설명)
├── base/                             # 환경 공통 K8s 리소스
│   ├── api-deployment.yaml
│   ├── api-service.yaml
│   ├── front-deployment.yaml
│   ├── front-service.yaml
│   ├── ingress.yaml
│   └── kustomization.yaml
└── overlays/
    └── dev/                          # dev 환경 전용 오버라이드
        ├── kustomization.yaml        # namespace + 이미지 태그 지정 (CI가 이 파일을 수정함)
        └── namespace.yaml
```

**ArgoCD Application 정의** (`gitops/argocd/engame-dev-application.yaml`):
```yaml
spec:
  source:
    repoURL: https://github.com/xxxx/study-k8s-infra.git
    targetRevision: main
    path: gitops/overlays/dev
  destination:
    namespace: engame-dev
  syncPolicy:
    automated:
      prune: true       # Git에서 삭제된 리소스는 클러스터에서도 삭제
      selfHeal: true     # 클러스터에서 수동으로 뭘 바꿔도 Git 상태로 되돌림
    syncOptions:
      - CreateNamespace=true
```
이 파일을 클러스터에 적용해야 ArgoCD가 이 앱을 인식합니다:
```bash
kubectl apply -f gitops/argocd/engame-dev-application.yaml
```

**base 리소스 요약**:
| 리소스 | 이름 | 주요 내용 |
|---|---|---|
| Deployment | `engame-api` | replicas 1, `DB_HOST/PORT/NAME/USERNAME`은 평문 env, `DB_PASSWORD`만 Secret(`engame-db-credentials`) 참조. readiness/liveness probe: `/api/leaderboard` |
| Service | `api` | 8080 포트. **서비스 이름이 "api"인 점 주의** (front의 nginx가 `http://api:8080`으로 참조하기 때문) |
| Deployment | `engame-front` | replicas 2, readiness/liveness probe: `/` |
| Service | `engame-front` | 80 포트 |
| Ingress | `engame-ingress` | ALB 사용(`kubernetes.io/ingress.class: alb`, internet-facing), **`engame-front` 서비스로만 라우팅** — api로의 직접 라우팅 규칙 없음 (13번 항목 참고) |

**overlays/dev/kustomization.yaml**의 `images:` 블록이 CI 파이프라인이 자동으로 고쳐쓰는 부분입니다 (12단계 참고).

**상태**: ✅ 완료, 실전 동작 검증됨(12단계).

---

## 10단계: GitHub OIDC (CI/CD용 IAM)

**목적**: GitHub Actions가 AWS 자격증명(액세스 키)을 코드/시크릿에 저장하지 않고, GitHub가 발급하는 JWT를 이용해 AWS STS에서 임시 자격증명을 받아오도록(OIDC 연동) 하기 위한 IAM 리소스.

**파일 위치**: `terraform/modules/08_github_oidc/`, `terraform/live/dev/08_github_oidc/terragrunt.hcl`

**핵심 설정값**:
```hcl
inputs = {
  github_org = "xxxx"
  repo_names = ["study-k8s-engame-api", "study-k8s-engame-front", "study-k8s-infra"]
}
```

**생성되는 리소스**:
1. `aws_iam_openid_connect_provider` — url `https://token.actions.githubusercontent.com`
2. IAM Role `github-actions-engame-deploy` — 위 3개 저장소에서 오는 토큰만 assume 가능하도록 trust policy 제한
3. IAM Role Policy — ECR push 권한

**apply 시 특이사항**: 이 모듈은 **IAM 리소스를 생성하는 민감한 작업**이라, Claude Code 자동 모드 classifier가 자동 apply를 차단했고, 사용자가 직접 `terragrunt apply`를 실행함.

**재현 방법**:
```bash
cd terraform/live/dev/08_github_oidc
terragrunt plan   # OIDC provider 1 + IAM Role 1 + Policy 1, 총 3개 생성 확인
terragrunt apply
terragrunt output  # role_arn 확인
```

**결과 확인된 값**:
```
role_arn = arn:aws:iam::xxx:role/github-actions-engame-deploy
```
이 값이 양쪽 `ci-cd.yml`의 `ROLE_ARN` 환경변수와 정확히 일치해야 합니다 (11단계).

**상태**: ✅ 완료, apply 및 값 일치 확인됨.

---

## 11단계: CI/CD 파이프라인 설계 (Black Duck → Trivy)

**배경**: 처음엔 취약점 스캔 단계에 **Black Duck**을 넣으려 했으나, Black Duck은 Synopsys(현 Black Duck Software)의 **상용 유료 제품**이라 서버/라이선스/API 토큰이 필요하다는 걸 확인. "무료 아니었어?"라는 질문에 답하면서 오픈소스 무료 대안인 **Trivy**로 최종 결정.

**파이프라인 흐름 (양쪽 저장소 공통 구조)**:
```
checkout → 언어별 빌드 → OIDC로 AWS 인증 → ECR 로그인 → 도커 이미지 빌드
→ Trivy 스캔 → ECR push → GitOps 리포(study-k8s-infra) clone → 이미지 태그 갱신 → 커밋/push
```

**engame_api용 `.github/workflows/ci-cd.yml` 핵심 설정**:
```yaml
on:
  push:
    branches: [main]
permissions:
  id-token: write   # OIDC 토큰 발급에 필요
  contents: read
env:
  AWS_REGION: ap-northeast-2
  ECR_REGISTRY: xxx.dkr.ecr.ap-northeast-2.amazonaws.com
  ECR_REPOSITORY: usb-dev-engame-api
  ROLE_ARN: arn:aws:iam::xxx:role/github-actions-engame-deploy
```
빌드: `./mvnw -B package -DskipTests` (JDK 17, Temurin)
Trivy 스텝:
```yaml
- name: Scan image with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:${{ github.sha }}
    format: table
    severity: CRITICAL,HIGH
    exit-code: '0'   # ⚠️ 지금은 뭘 찾아도 파이프라인을 안 막음 (fail-open). 13번 항목 참고
```
GitOps 업데이트 스텝:
```yaml
- name: Update gitops repo
  env:
    GITOPS_TOKEN: ${{ secrets.GITOPS_REPO_TOKEN }}
  run: |
    git clone https://x-access-token:${GITOPS_TOKEN}@github.com/xxxx/study-k8s-infra.git
    cd study-k8s-infra/gitops/overlays/dev
    yq -i '(.images[] | select(.name == "engame-api").newTag) = "${{ github.sha }}"' kustomization.yaml
    git commit -m "chore: update engame-api image to ${{ github.sha }}"
    git push
```

**engame_front용 `ci-cd.yml`**: 구조 동일, 차이점만:
- 빌드: `npm ci && npm run build` (Node 20)
- `ECR_REPOSITORY: usb-dev-engame-front`
- kustomization의 `engame-front` 이미지 태그를 갱신

**필요한 GitHub Secret**: 양쪽 저장소(`study-k8s-engame-api`, `study-k8s-engame-front`) 모두에 `GITOPS_REPO_TOKEN`이라는 이름으로 GitHub PAT 등록 필요.

**1) PAT 발급 절차** (Fine-grained token 권장 — classic보다 권한 범위를 좁게 잡을 수 있어 더 안전):
1. `https://github.com/settings/tokens?type=beta` 접속 → **Generate new token**
2. **Repository access**: "Only select repositories" 선택 → `study-k8s-infra` 하나만 선택 (다른 저장소까지 권한 줄 필요 없음)
3. **Permissions** → **Repository permissions** → **Contents**: `Read and write`로 설정 (GitOps 리포에 커밋/push해야 하므로 이 권한만 있으면 됨)
4. **Expiration**: 원하는 기간 설정 (만료 시 파이프라인이 조용히 막히므로 13-9 항목 참고해서 만료일 기록해둘 것)
5. **Generate token** 클릭 → 생성된 토큰 값 복사 (이 화면을 벗어나면 다시 못 봄, 꼭 그 자리에서 복사)

> Classic token으로 발급할 경우엔 scope 목록에서 `repo` 전체를 체크하면 되지만, 권한 범위가 훨씬 넓어지므로(모든 저장소에 대한 전체 권한) 위 Fine-grained 방식을 권장.

**2) 시크릿 등록 절차** (아래를 `study-k8s-engame-api`, `study-k8s-engame-front` 양쪽 저장소에 각각 반복):
1. 저장소 페이지 → **Settings** 탭
2. 왼쪽 메뉴 **Secrets and variables** → **Actions**
3. **New repository secret** 클릭
4. Name: `GITOPS_REPO_TOKEN`, Secret: 위에서 복사한 토큰 값 입력 → **Add secret**

**상태**: ✅ 설계 완료, 파일 작성 완료 (12단계에서 실제 push/검증).

---

## 12단계: 파이프라인 실전 검증

이 단계는 위에서 작성한 파이프라인이 실제로 끝까지 동작하는지 검증한 기록입니다.

### 12-1. GITOPS_REPO_TOKEN 발급 및 등록
사용자가 직접 GitHub에서 Fine-grained PAT를 발급하고, 양쪽 저장소에 시크릿으로 등록 완료.

### 12-2. `ci-cd.yml` 커밋 & push 시도 → 첫 실패
```bash
git add .github/workflows/ci-cd.yml
git commit -m "..."
git push origin main
```
결과:
```
! [remote rejected] main -> main (refusing to allow a Personal Access Token
  to create or update workflow `.github/workflows/ci-cd.yml` without `workflow` scope)
```
**원인**: 로컬 git push에 쓰이는 자격증명(macOS 키체인 `osxkeychain`에 저장된 PAT — `GITOPS_REPO_TOKEN`과는 별개의, 로컬 git 인증용 PAT)에 `workflow` scope가 없었음. `.github/workflows/` 경로 파일을 push하려면 GitHub이 이 scope를 요구함.

**해결 절차**:
1. `https://github.com/settings/tokens` 접속 (Classic tokens 목록)
2. 로컬 git push에 실제로 쓰이고 있는 토큰을 찾아서 이름 클릭 → **Edit**
3. Scope 체크박스에서 **`workflow`** 추가로 체크
4. 하단 **Update token** 클릭 — classic 토큰은 scope를 수정해도 토큰 값 자체는 안 바뀌므로, macOS 키체인(`osxkeychain`)을 다시 설정할 필요 없이 다음 push부터 바로 반영됨
5. `git push origin main` 재시도 → 성공
```
engame_api: 4a6e0ce ci: add CI/CD pipeline...  → push 성공
engame_front: ef4b345 Changes                   → push 성공 (front는 문제 없이 바로 됨)
```

### 12-3. GitOps 리포 자동 커밋 확인
파이프라인 실행 후 `study-k8s-infra`에 자동 커밋 2개 생성됨:
```
7900990 chore: update engame-api image to d5619d6ed2b4574faf608a3f3b247249b74e0b7e
09865b2 chore: update engame-front image to ef4b345d6e9b1e3b4efcf5179da46869121ca49a
```
→ CI → ECR → GitOps 리포 업데이트까지의 체인 검증 완료.

### 12-4. Trivy 실제 탐지 여부 검증 (일부러 취약점 주입)
`engame_api/Dockerfile`의 런타임 베이스 이미지를 임시로 오래된 이미지로 교체:
```diff
- FROM eclipse-temurin:17-jre
+ FROM openjdk:8u212-jre
```
push 후 Trivy 스캔 결과:
- **OS 패키지(Debian 9.9) 레이어**: 총 161개 (CRITICAL 26, HIGH 135)
- **Java 애플리케이션(jar) 레이어**: 총 18개 (CRITICAL 3, HIGH 15) — 이건 테스트와 무관하게 **실제 `pom.xml` 의존성 버전 문제**로 발견된 것:

| 라이브러리 | 설치된 버전 | 심각도 | Fixed Version | CVE |
|---|---|---|---|---|
| `jackson-databind` | 2.19.0 | HIGH | 2.18.8 / 2.21.4 / 3.1.4 | CVE-2026-54512, CVE-2026-54513 |
| `tomcat-embed-core` | 10.1.41 | CRITICAL | 9.0.118 / 10.1.55 / 11.0.22 | CVE-2026-41293 외 다수 |
| `spring-boot` | 3.5.0 | (parent) | 3.5.14 / 4.0.6 | CVE-2026-40973 |
| `spring-core` | 6.2.7 | HIGH | 6.2.11 | CVE-2025-41249 |

→ Trivy가 OS 레이어 + 애플리케이션 의존성 레이어 둘 다 정상적으로 스캔한다는 것 확인.

### 12-5. 배포 자동화 실전 검증 (실패 케이스로 오히려 확실히 증명됨)
`kubectl get pods -n engame-dev` 확인 결과, 위 취약 이미지로 **실제 새 파드가 자동 배포**됨:
```
engame-api-5cb89648d-vm7jq   0/1   CrashLoopBackOff   ...
```
로그:
```
Exception in thread "main" java.lang.UnsupportedClassVersionError:
org/springframework/boot/loader/launch/JarLauncher has been compiled by a more
recent version of the Java Runtime (class file version 61.0), this version of
the Java Runtime only recognizes class file versions up to 52.0
```
**해석**: JDK 17로 컴파일된 애플리케이션을 JRE 8 위에서 실행하려다 크래시. 이건 Trivy가 막아서가 아니라(현재 `exit-code: 0`이라 안 막음), 애초에 JRE 버전 자체가 안 맞아서 발생한 예상된 실패. 오히려 이 크래시 덕분에 **"파이프라인이 취약점을 발견해도 배포를 막지 않고 그대로 진행한다"**는 현재 동작(fail-open)이 실전에서 명확히 증명됨. 기존 정상 파드(`engame-api-7647b9fbbb-424jn`)는 그대로 유지되어 서비스 중단은 없었음.

### 12-6. 원복
```diff
- FROM openjdk:8u212-jre
+ FROM eclipse-temurin:17-jre
```
커밋 `1669be3` push → 파이프라인 재실행 → `engame-api-789c7544c9-g9dqg` (이미지 태그 `1669be3...`)로 정상 `Running` 확인, 크래시 파드는 자동 정리됨.

**상태**: ✅ 전체 체인(push → 빌드 → 스캔 → ECR → GitOps 커밋 → ArgoCD 자동 배포) 정상/실패 양방향 실전 검증 완료.

---

## 13. 현재 남아있는 작업 / 확인 필요 항목

우선순위 순으로 정리했습니다.

### 13-1. (중요) Trivy를 실제 게이트로 전환
지금은 `exit-code: '0'`이라 CRITICAL 취약점이 나와도 배포가 그대로 진행됩니다. 12-4에서 실제로 `tomcat-embed-core`, `spring-boot` 등 진짜 CVE가 발견됐는데도 배포까지 이어졌습니다. 안정화 단계에서는:
```yaml
severity: CRITICAL
exit-code: '1'
```
로 바꿔서 CRITICAL 발견 시 파이프라인을 실제로 멈추도록 강화 필요. (양쪽 `ci-cd.yml` 모두 수정 필요)

### 13-2. (중요) 실제 발견된 의존성 취약점 패치
`engame_api/pom.xml`의 `spring-boot-starter-parent` 버전을 3.5.0 → 3.5.14 이상으로, 그리고 `jackson-databind`/`tomcat-embed-core`가 spring-boot-starter-parent에 딸려오는 버전이라면 parent 버전만 올려도 같이 해결될 가능성이 높음. 별도 CVE가 남으면 개별 `<dependencyManagement>`로 버전 오버라이드 필요.

### 13-3. ArgoCD `ApplicationSet` 컨트롤러 에러 (현재 서비스에 영향 없음)
`argocd-applicationset-controller` 파드가 계속 `CrashLoopBackOff`/`Error` 상태 (`no matches for kind "ApplicationSet"` — CRD가 클러스터에 설치 안 돼 있음). 지금은 `Application`(단수) 리소스만 쓰고 `ApplicationSet`은 안 쓰기 때문에 실제 배포(`engame-dev` Application은 `Synced/Healthy`)에는 영향 없음. 다만:
- 나중에 여러 환경(dev/prod)을 `ApplicationSet`으로 한 번에 관리하고 싶으면 CRD부터 설치해야 함
- 당장은 아니어도 불필요한 에러 로그/재시작이 계속 쌓이니, ApplicationSet CRD를 설치하거나 아예 이 컨트롤러 배포를 비활성화하는 정리가 필요

### 13-4. ArgoCD 설치 자체가 코드화(IaC)돼 있지 않음
현재 ArgoCD 컨트롤 플레인은 (추정상) `kubectl apply -f <공식 install.yaml>`로 수동 설치된 상태로 보이고, 이 저장소에는 그 설치 매니페스트나 Helm values가 없습니다. 재해복구(disaster recovery)나 재현성을 위해 Helm chart(`argo-helm/argo-cd`) + values 파일을 이 저장소에 코드로 남기는 걸 권장합니다.

### 13-5. AWS Load Balancer Controller Helm install도 코드화 안 돼 있음
5단계와 동일한 이슈. IAM 부분은 Terraform이지만 실제 `helm install` 명령 자체는 저장소에 기록이 없음.

### 13-6. `trivy-action@master` 버전 미고정
`@master`를 쓰면 액션 쪽에 breaking change가 생겼을 때 예고 없이 파이프라인이 깨질 수 있음. `@0.28.0`처럼 특정 버전으로 고정 권장.

### 13-7. ECR 자체 스캔(`scan_on_push: true`)과 CI의 Trivy 스캔 중복
`terraform/modules/07_ecr/main.tf`에서 ECR 자체 취약점 스캔도 이미 켜져 있어서, 사실상 스캔이 두 군데(ECR 네이티브 + CI Trivy)에서 이루어지고 있음. 당장 문제는 아니지만, 둘 중 하나로 통일하거나 "CI는 배포 게이트용, ECR은 사후 모니터링용"처럼 역할을 명확히 나누는 정리가 필요.

### 13-8. Ingress가 API로 직접 라우팅하지 않음 (설계상 의도된 것, 확인만)
`gitops/base/ingress.yaml`은 `engame-front` 서비스로만 라우팅합니다. `/api/*` 요청은 ALB를 거치지 않고 **front 컨테이너 안의 nginx(`nginx.conf`)가 `location /api/ { proxy_pass http://api:8080/api/; }`로 클러스터 내부에서 백엔드로 프록시**하는 구조입니다. 의도된 설계로 보이나, 팀에 공유할 때는 "API가 별도 공인 엔드포인트로 노출되지 않는다"는 점을 명확히 인지시켜야 함.

### 13-9. GitHub PAT(`GITOPS_REPO_TOKEN`) 만료 관리
Fine-grained PAT는 만료일이 있습니다. 만료되면 12-3 단계(GitOps 리포 업데이트)가 인증 실패로 조용히 막힐 수 있으니, 만료일을 기록해두고 갱신 알림/절차를 마련할 필요가 있음.

### 13-10. `prod` 환경 미구축
지금은 `terraform/live/dev`만 있고 `live/prod`는 없습니다. dev와 동일한 모듈 구조를 `env.hcl`만 `env = "prod"`로 바꿔서 복제하고, RDS는 `skip_final_snapshot = false`로, 인스턴스 사이즈업 등을 고려해서 별도로 구성해야 함.

### 13-11. 모니터링/로깅 스택 없음
Prometheus/Grafana, 혹은 CloudWatch Container Insights 등 클러스터/애플리케이션 모니터링이 아직 구축되지 않음.
