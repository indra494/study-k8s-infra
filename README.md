# study-k8s-infra

`engame` 프로젝트의 AWS 인프라(Terraform/Terragrunt)와 배포 매니페스트(ArgoCD GitOps)를 관리하는 저장소입니다.

관련 저장소:
- [`study-k8s-engame-api`](https://github.com/xxxx/study-k8s-engame-api) — Spring Boot 백엔드
- [`study-k8s-engame-front`](https://github.com/xxxx/study-k8s-engame-front) — React 프론트엔드

> **현재 상태**: dev 환경 AWS 리소스는 비용 절감을 위해 전체 `terragrunt destroy` 완료된 상태입니다 (코드는 그대로 남아있음). 다시 띄우려면 [`docs/SETUP_DETAIL.md`](./docs/SETUP_DETAIL.md)의 1~10단계를 순서대로 `terragrunt apply`하면 됩니다.

---

## 디렉토리 구조

```
study-k8s-infra/
├── bootstrap/                # Terraform state 백엔드(S3 + DynamoDB) 최초 생성용 — 한 번만 실행
│
├── terraform/
│   ├── modules/               # 재사용 가능한 인프라 "설계도" (환경과 무관한 순수 리소스 정의)
│   │   ├── 01_vpc/
│   │   ├── 02_eks/
│   │   ├── 03_eks_nodes/
│   │   ├── 04_eks_lb_controller/
│   │   ├── 05_rds/
│   │   ├── 06_bastion/
│   │   ├── 07_ecr/
│   │   └── 08_github_oidc/
│   │
│   └── live/dev/               # 위 모듈에 dev 환경 실제 값을 주입해서 배포하는 곳 (prod 추가 시 live/prod/ 생성)
│       ├── 01_vpc/ ~ 08_github_oidc/   # 모듈 이름과 1:1 대응, 숫자 = 의존관계/적용 순서
│       └── env.hcl                     # 환경 이름(env=dev) 정의
│
├── gitops/                     # ArgoCD가 감시하는 배포 매니페스트 (Kustomize 구조)
│   ├── argocd/                 # ArgoCD Application 정의 (이 저장소의 어느 경로를 감시할지)
│   ├── base/                   # 환경 공통 K8s 리소스 (Deployment/Service/Ingress)
│   └── overlays/dev/           # dev 환경 전용 값 (namespace, 이미지 태그) — CI가 자동으로 갱신하는 부분
│
├── docs/                       # 상세 문서 (아래 표 참고)
├── .gitignore
└── README.md
```

## 한 줄 요약: 각 레이어가 하는 일

| 레이어 | 역할 |
|---|---|
| `bootstrap/` | Terraform state를 어디에 저장할지(S3) 정하는, 다른 모든 것의 전제조건 |
| `terraform/modules/` | "이런 리소스를 만드는 법"이라는 재사용 템플릿. 환경 값이 없어서 그 자체로는 배포 안 됨 |
| `terraform/live/dev/` | 그 템플릿에 dev 환경 실제 값(이름, CIDR 등)을 넣어 실제로 AWS에 반영하는 곳. **실제 작업은 항상 이 안에서** |
| `gitops/` | "쿠버네티스 클러스터 안에 뭘 띄울지"를 선언한 Git. ArgoCD가 이 폴더를 계속 감시하다가 변경되면 자동으로 클러스터에 반영 (CI가 이미지 태그를 자동으로 갱신하는 대상이기도 함) |

인프라(AWS 리소스)와 배포(K8s 리소스)가 이 저장소 안에서 `terraform/`과 `gitops/`로 물리적으로 분리돼 있다는 점이 이 구조의 핵심입니다. 전체 흐름과 왜 이렇게 나눴는지는 [`docs/ARCHITECTURE_PIPELINE.md`](./docs/ARCHITECTURE_PIPELINE.md)에 자세히 설명돼 있습니다.

## 문서 (`docs/`)

| 문서 | 내용 |
|---|---|
| [`SETUP_DETAIL.md`](./docs/SETUP_DETAIL.md) | 부트스트랩부터 CI/CD까지 13단계 상세 설정값 + 재현 명령어 + 현재 남은 작업 목록 |
| [`ARCHITECTURE_PIPELINE.md`](./docs/ARCHITECTURE_PIPELINE.md) | 전체 아키텍처 다이어그램, push 한 번이 배포까지 이어지는 전체 흐름, 설계 결정 이유 |
| [`KUBERNETES_CHEATSHEET.md`](./docs/KUBERNETES_CHEATSHEET.md) | kubectl 개념 + 명령어 모음 (자주 쓰는 것 / 기타) |
| [`TERRAFORM_CHEATSHEET.md`](./docs/TERRAFORM_CHEATSHEET.md) | Terraform/Terragrunt 개념 + 명령어 모음 (자주 쓰는 것 / 기타) |

## 빠른 시작

```bash
# 1. 처음 한 번만: state 백엔드 생성
cd bootstrap && terraform init && terraform apply

# 2. 인프라 순서대로 적용 (01_vpc부터 08_github_oidc까지)
cd terraform/live/dev
terragrunt run --all -- apply

# 3. ArgoCD를 클러스터에 설치한 뒤 (docs/SETUP_DETAIL.md 9단계 참고), Application 등록
kubectl apply -f gitops/argocd/engame-dev-application.yaml
```

전체 삭제가 필요할 땐 역순으로:
```bash
cd terraform/live/dev
terragrunt run --all --non-interactive -- destroy
```
(ECR에 이미지가 남아있으면 실패하니, `docs/TERRAFORM_CHEATSHEET.md` 1-3 참고해서 먼저 비울 것)
