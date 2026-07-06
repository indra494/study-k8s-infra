# Terraform / Terragrunt 개념 + 명령어 모음

이 문서는 [`KUBERNETES_CHEATSHEET.md`](KUBERNETES_CHEATSHEET.md)와 같은 형식으로, Terraform/Terragrunt가 낯선 사람도 이 저장소(`terraform/`)를 바로 다룰 수 있도록 **개념 요약 → 자주 쓰는 명령어 → 기타 명령어** 순으로 정리했습니다. 이 저장소의 실제 모듈 구조·설정값은 [`SETUP_DETAIL.md`](SETUP_DETAIL.md), 전체 흐름은 [`ARCHITECTURE_PIPELINE.md`](ARCHITECTURE_PIPELINE.md)를 참고하세요.

**이 저장소의 Terragrunt 버전은 `1.1.0`**입니다. 이 버전부터 CLI가 크게 바뀌어서(`run-all` 같은 옛날 명령이 그대로 안 먹힘), 아래 명령어는 전부 **이 버전 기준**으로 맞춰 정리했습니다. 다른 環경에서 옛날 버전을 쓴다면 문법이 다를 수 있습니다.

---

## 0. 핵심 개념 5분 요약

| 개념 | 한 줄 설명 |
|---|---|
| **Terraform (OpenTofu)** | "AWS에 이런 리소스들이 있어야 한다"를 코드(`.tf`)로 선언하면, 실제 상태와 비교해서 차이만큼 만들거나/고치거나/지워주는 도구 |
| **State** | Terraform이 "지금 실제로 뭐가 만들어져 있는지" 기억해두는 파일. 이 저장소는 `bootstrap/`에서 만든 S3 버킷(`usb-terraform-state-2026`)에 원격 저장하고, DynamoDB 테이블(`terraform-lock`)로 동시 실행 충돌을 방지함 |
| **Module** (`terraform/modules/`) | 재사용 가능한 리소스 묶음의 "설계도" (예: `02_eks` 모듈 = EKS 클러스터를 만드는 코드 뭉치) |
| **Live / 실제 배포 단위** (`terraform/live/dev/`) | 그 설계도에 "이 환경에서는 이 값으로 만들어줘"라고 실제 값을 넣어 적용하는 곳. `prod`를 추가하면 `terraform/live/prod/`가 생기는 구조 |
| **Terragrunt** | Terraform 위에 얹는 오케스트레이션 도구. 이 저장소처럼 모듈이 8개(`01_vpc`~`08_github_oidc`)로 쪼개져 있고 서로 의존관계(`dependency` 블록)가 있을 때, 순서를 자동으로 계산해서 실행해줌. **이 저장소에서는 `terraform` 명령을 직접 쓰지 않고 거의 항상 `terragrunt`를 씀** |
| **plan** | "지금 코드대로 apply하면 뭐가 바뀌는지" 미리보기 (실제로 아무것도 안 바꿈) |
| **apply** | 실제로 AWS에 반영 |
| **destroy** | 그 모듈이 만든 리소스를 전부 삭제 |

**꼭 기억할 것**: `terraform/live/dev/` 안의 각 폴더(`01_vpc`, `02_eks`, ...)는 숫자가 의존관계 순서를 나타냅니다. **apply할 땐 숫자 순서대로, destroy할 땐 역순으로** 해야 하고, 여러 모듈을 한 번에 하려면 아래 2-1의 `run --all`을 쓰면 Terragrunt가 이 순서를 자동으로 계산해줍니다.

---

## 1. 자주 쓰는 명령어

### 1-1. 단일 모듈 작업 (제일 많이 씀)
```bash
cd terraform/live/dev/02_eks

# 처음 한 번, 혹은 provider/모듈 버전이 바뀌었을 때
terragrunt init

# 지금 코드대로 apply하면 뭐가 바뀌는지 미리보기 (항상 apply 전에 먼저 볼 것)
terragrunt plan

# 실제 반영 (프롬프트에서 yes 입력 필요)
terragrunt apply

# 자동으로 yes 처리하고 싶을 때 (스크립트/CI에서 씀, 사람이 직접 할 땐 plan 결과 꼭 보고 나서 신중히)
terragrunt apply -auto-approve

# 이 모듈이 만든 리소스 완전 삭제
terragrunt destroy

# output 값 확인 (예: 08_github_oidc의 role_arn 확인할 때 실제로 씀)
terragrunt output
terragrunt output role_arn   # 특정 output 하나만
```

### 1-2. 여러 모듈을 한 번에 (의존성 자동 계산)
```bash
cd terraform/live/dev

# 이 아래 모든 모듈에 대해 plan (의존 순서대로 dependents부터 표시됨)
terragrunt run --all -- plan

# 전체 apply (하나씩 순서대로, 앞 모듈 output을 뒷 모듈이 자동으로 받아씀)
terragrunt run --all -- apply

# 전체 destroy (반대로 dependents부터 먼저 지움 - 자동 계산됨)
terragrunt run --all -- destroy

# 사람이 매번 y 안 눌러도 되게 (destroy 전체처럼 반복적인 확인이 귀찮을 때)
terragrunt run --all --non-interactive -- destroy
```
> **실전 팁**: `run --all -- destroy`를 실행하면 시작 전에 "어떤 순서로 destroy할지" 트리 형태로 미리 보여줍니다. 꼭 한번 눈으로 확인하고 진행하세요 (아래 예시처럼 dependents가 먼저, 그 아래로 의존하는 모듈이 중첩되어 표시됨).
> ```
> 06_bastion
>     ├── 05_rds
>     │   ├── 02_eks
>     │   │   ╰── 01_vpc
>     │   ╰── 01_vpc
>     ╰── 01_vpc
> ```

### 1-3. 실제로 겪었던 특이 케이스: ECR destroy 실패
`aws_ecr_repository`는 리포지토리 안에 이미지가 남아있으면 기본적으로 삭제가 안 됩니다 (`force_delete`가 코드에 설정 안 돼 있으면). 이럴 땐:
```bash
# 이미지 목록 확인
aws ecr list-images --repository-name usb-dev-engame-api --region ap-northeast-2

# 이미지 전부 삭제 (manifest list가 있으면 한 번에 안 지워질 수 있어 2번 반복 필요할 수 있음)
aws ecr batch-delete-image --repository-name usb-dev-engame-api --region ap-northeast-2 \
  --image-ids "$(aws ecr list-images --repository-name usb-dev-engame-api --region ap-northeast-2 --query imageIds --output json)"

# 비운 후 그 모듈만 다시 destroy
cd terraform/live/dev/07_ecr && terragrunt destroy -auto-approve
```

### 1-4. 상태(state) 확인
```bash
# 이 모듈의 state에 뭐가 들어있는지 목록
terragrunt state list

# 특정 리소스의 실제 값 확인 (민감정보 포함될 수 있음 주의)
terragrunt state show aws_eks_cluster.this
```

---

## 2. 기타 (자주는 안 쓰지만 알아두면 좋은 것)

### 2-1. 코드 검증/포맷
```bash
# 코드 문법이 유효한지만 체크 (AWS 호출 없음, 빠름)
terragrunt validate

# .tf 파일 포맷 정리 (스타일 통일)
terragrunt run -- fmt -recursive
```

### 2-2. state 직접 조작 (위험 - 잘 모르면 만지지 말 것)
```bash
# state 안에서 리소스 이름을 바꾸고 싶을 때 (실제 AWS 리소스는 안 건드리고 Terraform이 "기억하는 이름"만 변경)
terragrunt state mv aws_instance.old aws_instance.new

# state에서만 빼기 (AWS에는 그대로 남아있음 - "이제부터 Terraform이 이건 관리 안 해" 선언)
terragrunt state rm aws_instance.this

# 이미 AWS에 있는 리소스를 Terraform 관리 대상으로 편입 (콘솔에서 수동 생성한 걸 나중에 코드화할 때)
terragrunt import aws_instance.this i-0123456789abcdef0
```

### 2-3. 잠금(lock) 문제 해결
```bash
# 다른 apply가 비정상 종료돼서 DynamoDB에 lock이 안 풀렸을 때
terragrunt force-unlock <LOCK_ID>
```

### 2-4. 리소스 강제 재생성
```bash
# 특정 리소스를 "변경 예정" 상태로 표시 - 다음 apply 때 삭제 후 재생성됨
terragrunt run -- taint aws_instance.this

# taint 취소
terragrunt run -- untaint aws_instance.this
```

### 2-5. 의존관계 시각화 / 디버깅
```bash
# 이 저장소 하위 모든 모듈의 의존관계를 그래프로 (Graphviz 필요)
terragrunt dag graph

# 이 폴더에서 인식되는 terragrunt 설정 목록 확인
terragrunt list

# 최종적으로 병합된 terragrunt 설정을 눈으로 확인 (include/locals가 뭘로 치환됐는지 디버깅용)
terragrunt render -json
```

### 2-6. 특정 리소스만 콕 집어서 (위험 - 웬만하면 안 쓰는 게 좋음)
```bash
# plan/apply 범위를 특정 리소스로 제한 (전체 그림을 못 보게 돼서 의존성 있는 인프라에서는 사고 위험 큼)
terragrunt plan -target=aws_instance.bastion
```

### 2-7. 워크스페이스 (이 저장소는 안 씀 - `live/dev`, `live/prod` 폴더 분리 방식을 쓰기 때문)
```bash
terragrunt run -- workspace list
terragrunt run -- workspace new staging
```

---

## 3. 자주 헷갈리는 것 정리

| 헷갈리는 것 | 정리 |
|---|---|
| `terraform` vs `terragrunt` | 이 저장소는 모듈이 여러 개로 쪼개져 있고 서로 output을 참조(`dependency` 블록)하기 때문에, `terraform` 명령을 직접 쓰면 백엔드 설정(S3/DynamoDB)이나 의존성 값을 손수 다 챙겨야 함. **이 저장소에서는 항상 `terragrunt`로 실행** |
| `terragrunt plan` (단일 모듈) vs `terragrunt run --all -- plan` (전체) | 폴더 하나(`cd 02_eks`)에 들어가서 하면 그 모듈만, `live/dev` 루트에서 `run --all`을 쓰면 하위 전체 모듈을 의존성 순서에 맞게 처리 |
| `run-all destroy` (옛 문법) vs `run --all -- destroy` (1.1.0 신 문법) | Terragrunt 1.1.0부터 CLI가 재설계되어 `run-all`을 명령어 앞에 그냥 붙이면 `unknown command` 에러가 남. 반드시 `terragrunt run --all -- <명령>` 형태로 써야 함 |
| `--terragrunt-non-interactive` (옛 플래그) vs `--non-interactive` (1.1.0) | 마찬가지로 신버전에서 플래그 이름이 `terragrunt-` 접두어 없이 짧아짐 |
| apply 순서 vs destroy 순서 | apply는 의존하는 대상을 먼저 만들어야 하니 `01_vpc → 02_eks → ... → 08_github_oidc` 순. destroy는 반대로 **의존하고 있는 쪽(dependent)부터 먼저** 지워야 함(예: `06_bastion`이 `05_rds`를 참조하니 bastion을 먼저 지워야 rds를 지울 수 있음). `run --all -- destroy`를 쓰면 이 순서를 Terragrunt가 알아서 계산해줌 |
| `plan`에서 아무 변경 없음(no changes)인데 실제로는 뭔가 바뀐 것 같을 때 | 클러스터/리소스를 콘솔이나 `kubectl`로 수동 변경한 경우, Terraform이 관리하지 않는 필드(예: EKS 애드온, k8s 리소스 자체)일 가능성이 큼. Terraform은 자기가 만든 필드만 추적함 |
| `-auto-approve`를 습관적으로 쓰는 것 | 특히 IAM, VPC, RDS처럼 되돌리기 어렵거나 데이터 손실이 걸린 모듈은 **plan을 반드시 먼저 눈으로 확인**하고 apply하는 습관 권장 (이 프로젝트에서도 `08_github_oidc`처럼 IAM 리소스 생성은 자동 실행이 막히고 사람이 직접 확인 후 진행했던 사례가 있음) |
