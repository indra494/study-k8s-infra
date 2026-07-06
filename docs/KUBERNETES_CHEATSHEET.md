# Kubernetes 개념 + kubectl 명령어 모음

이 문서는 쿠버네티스 자체가 낯선 사람이 이 프로젝트(`engame-dev` 네임스페이스, ArgoCD GitOps)를 다루면서 바로 써먹을 수 있도록, **개념 요약 → 자주 쓰는 명령어 → 기타 명령어** 순으로 정리한 문서입니다. 인프라 설정 자체는 [`SETUP_DETAIL.md`](SETUP_DETAIL.md), 전체 흐름은 [`ARCHITECTURE_PIPELINE.md`](ARCHITECTURE_PIPELINE.md)를 참고하세요.

---

## 0. 핵심 개념 5분 요약

쿠버네티스는 "이런 상태로 유지해줘"라고 **선언**하면, 컨트롤러들이 계속 그 상태를 맞추려고 알아서 움직이는 시스템입니다. 이 프로젝트에서 실제로 쓰는 오브젝트만 추립니다.

| 오브젝트 | 한 줄 설명 | 이 프로젝트에서의 예 |
|---|---|---|
| **Pod** | 컨테이너 1개(또는 여러 개)를 담는 가장 작은 실행 단위. 직접 만들 일은 거의 없고 Deployment가 대신 만들어줌 | `engame-api-xxxxx-xxxxx` |
| **Deployment** | "이 이미지로 파드를 N개 유지해줘"를 선언. 이미지가 바뀌면 새 파드를 만들고 기존 파드를 순차 교체(rolling update) | `engame-api`, `engame-front` |
| **Service** | 파드들 앞에 붙는 고정 내부 주소(DNS 이름). 파드는 재시작할 때마다 IP가 바뀌지만 Service 이름은 안 바뀜 | `api` (8080), `engame-front` (80) |
| **Ingress** | 클러스터 밖(인터넷)에서 들어오는 요청을 어떤 Service로 보낼지 정하는 라우팅 규칙. 이 프로젝트는 ALB Ingress Controller가 실제 로드밸런서를 만듦 | `engame-ingress` → `engame-front` |
| **Namespace** | 리소스를 논리적으로 격리하는 단위(폴더 같은 개념) | `engame-dev`, `argocd`, `kube-system` |
| **ArgoCD Application** | (쿠버네티스 기본 오브젝트는 아니고 ArgoCD가 추가한 CRD) "이 Git 경로를 계속 감시해서 클러스터에 반영해줘"라는 선언 | `engame-dev` (Application 이름) |

**꼭 기억할 것**: 이 클러스터는 ArgoCD가 `selfHeal: true`로 감시 중입니다. 즉 `kubectl apply`나 `kubectl edit`로 매니페스트를 직접 고쳐도, ArgoCD가 몇 분 안에 **Git에 있는 상태로 되돌려버립니다**. 그래서 이 클러스터에서는 "직접 고치기"보다 "Git(`gitops/` 폴더)을 고치고 push하기"가 정석입니다. 아래 명령어들은 대부분 **조회/디버깅용**이고, 실제 배포 변경은 GitOps 흐름을 따르는 걸 권장합니다.

---

## 1. 자주 쓰는 명령어

### 1-1. 상태 조회 (제일 많이 씀)
```bash
# 이 네임스페이스의 파드 목록 (STATUS, RESTARTS 확인용)
kubectl get pods -n engame-dev

# 파드가 어느 노드에 떴는지, IP까지 같이 보고 싶을 때
kubectl get pods -n engame-dev -o wide

# 실시간으로 계속 갱신해서 보고 싶을 때 (배포 직후 상태 지켜볼 때 유용)
kubectl get pods -n engame-dev -w

# Deployment 목록 (READY 3/3 같은 형태로 원하는 replica 수 대비 현재 수 확인)
kubectl get deploy -n engame-dev

# Service 목록 (내부 DNS 이름, 포트 확인)
kubectl get svc -n engame-dev

# Ingress 목록 (ALB 주소 확인 - ADDRESS 컬럼이 실제 접속 도메인)
kubectl get ingress -n engame-dev

# 네임스페이스 안의 웬만한 리소스를 한 번에
kubectl get all -n engame-dev
```

### 1-2. 로그/디버깅
```bash
# 특정 파드 로그 (이름은 위 get pods로 먼저 확인)
kubectl logs engame-api-xxxxx-xxxxx -n engame-dev

# 실시간 tail (배포 직후 에러 나는지 지켜볼 때)
kubectl logs -f engame-api-xxxxx-xxxxx -n engame-dev

# 방금 재시작한 크래시 파드의 "재시작 직전" 로그 (크래시 원인 파악할 때 필수)
kubectl logs engame-api-xxxxx-xxxxx -n engame-dev --previous

# 파드 상세 정보 (Events 섹션에 스케줄링 실패/이미지 pull 실패 등 원인이 다 나옴)
kubectl describe pod engame-api-xxxxx-xxxxx -n engame-dev

# 네임스페이스 전체 이벤트를 시간순으로 (뭔가 이상할 때 제일 먼저 볼 것)
kubectl get events -n engame-dev --sort-by=.lastTimestamp

# 파드 안에 직접 들어가서 확인 (Spring Boot 컨테이너면 sh만 있는 경우가 많음)
kubectl exec -it engame-api-xxxxx-xxxxx -n engame-dev -- /bin/sh
```

### 1-3. 배포/재기동
```bash
# 매니페스트 적용 (ArgoCD Application 자체를 처음 등록할 때 등)
kubectl apply -f gitops/argocd/engame-dev-application.yaml

# 코드/이미지 변경 없이 파드만 강제로 다시 띄우고 싶을 때 (설정 반영 등)
# 주의: GitOps 흐름과 무관하게 임시로 재시작하는 것 - 원인 해결은 아님
kubectl rollout restart deployment/engame-api -n engame-dev

# 롤아웃이 잘 진행되고 있는지(새 파드가 다 뜰 때까지) 지켜보기
kubectl rollout status deployment/engame-api -n engame-dev

# 방금 배포가 잘못됐을 때 직전 리비전으로 즉시 되돌리기 (ArgoCD가 있어도 응급 시 유용)
kubectl rollout undo deployment/engame-api -n engame-dev

# 롤아웃 히스토리(리비전 목록) 확인
kubectl rollout history deployment/engame-api -n engame-dev

# 특정 파드 하나만 삭제 (Deployment가 즉시 새로 하나 만들어서 채워줌 - 껐다 켜기 효과)
kubectl delete pod engame-api-xxxxx-xxxxx -n engame-dev

# replica 수 임시로 늘리기/줄이기 (Git의 값과 달라지면 ArgoCD가 다시 되돌림)
kubectl scale deployment/engame-front --replicas=3 -n engame-dev
```

### 1-4. ArgoCD 상태 확인
```bash
# ArgoCD가 관리하는 Application 목록과 동기화 상태 (Synced/OutOfSync, Healthy/Degraded)
kubectl get application -n argocd

# 특정 Application 상세 (마지막 sync 시각, 에러 메시지 등)
kubectl describe application engame-dev -n argocd

# argocd 네임스페이스 자체의 컴포넌트 상태 (서버가 죽었는지 등)
kubectl get pods -n argocd
```

### 1-5. 이미지/설정 확인
```bash
# 지금 각 파드가 실제로 어떤 이미지 태그로 떠 있는지 (배포가 제대로 됐는지 최종 확인)
kubectl get pods -n engame-dev -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# Secret 목록 확인 (내용은 기본적으로 안 보임 - 아래 "기타"에 디코딩 명령어 있음)
kubectl get secrets -n engame-dev

# ConfigMap 확인
kubectl get configmap -n engame-dev
```

---

## 2. 기타 (자주는 안 쓰지만 알아두면 좋은 것)

### 2-1. 클러스터/컨텍스트 관리
```bash
# 지금 붙어있는 클러스터가 어디인지 확인 (dev/prod 여러 개 다룰 때 실수 방지용으로 꼭 확인 습관 들이기)
kubectl config current-context

# 사용 가능한 컨텍스트(클러스터) 목록
kubectl config get-contexts

# 다른 클러스터로 전환
kubectl config use-context <context-name>

# EKS 클러스터의 kubeconfig를 새로 받아오기 (자격증명 만료/컨텍스트 꼬였을 때)
aws eks update-kubeconfig --region ap-northeast-2 --name usb-dev-eks
```

### 2-2. 리소스 사용량 (metrics-server 설치돼 있어야 동작)
```bash
kubectl top nodes
kubectl top pods -n engame-dev
```

### 2-3. 네트워크 디버깅
```bash
# 로컬 PC에서 클러스터 내부 서비스로 임시 터널 뚫기 (Ingress 없이 바로 확인하고 싶을 때)
kubectl port-forward svc/api 8080:8080 -n engame-dev
# 이후 localhost:8080으로 접속하면 클러스터 내부 api 서비스로 연결됨

# 파드 <-> 로컬 파일 복사
kubectl cp engame-dev/engame-api-xxxxx-xxxxx:/app/some.log ./some.log
```

### 2-4. 라벨/어노테이션/변경 미리보기
```bash
# 매니페스트 apply 전에 실제로 뭐가 바뀌는지 diff로 미리보기 (terraform plan과 비슷한 개념)
kubectl diff -f gitops/argocd/engame-dev-application.yaml

# 특정 필드만 콕 집어서 바로 수정 (긴급 패치용, GitOps와 어긋나므로 selfHeal이 곧 되돌림)
kubectl patch deployment engame-api -n engame-dev -p '{"spec":{"replicas":2}}'

# 라벨/어노테이션 추가
kubectl label pod engame-api-xxxxx-xxxxx -n engame-dev debug=true
kubectl annotate deployment engame-api -n engame-dev note="temp fix"
```

### 2-5. 권한/보안 확인
```bash
# 지금 내 계정으로 특정 동작이 가능한지 확인 (RBAC 디버깅용)
kubectl auth can-i delete pods -n engame-dev
kubectl auth can-i '*' '*' --all-namespaces   # 클러스터 관리자 권한인지 확인

# Secret 값 실제로 디코딩해서 보기 (조회 후 base64 디코딩 필요)
kubectl get secret engame-db-credentials -n engame-dev -o jsonpath='{.data.password}' | base64 -d
```

### 2-6. 노드 관리 (거의 안 씀 - 노드 자체 점검/교체 시에만)
```bash
# 특정 노드에 새 파드 스케줄링 막기 (점검 전)
kubectl cordon <node-name>

# 그 노드에 있는 파드들을 다른 노드로 안전하게 옮기기
kubectl drain <node-name> --ignore-daemonsets

# 점검 끝나고 다시 스케줄링 허용
kubectl uncordon <node-name>
```

### 2-7. 오브젝트 스펙 자체가 궁금할 때
```bash
# 특정 리소스 종류가 어떤 필드를 가질 수 있는지 공식 문서 없이 바로 조회
kubectl explain deployment.spec.strategy
kubectl explain pod.spec.containers.livenessProbe
```

---

## 3. 자주 헷갈리는 것 정리

| 헷갈리는 것 | 정리 |
|---|---|
| `kubectl apply -f x.yaml` vs GitOps | `apply`는 "지금 당장 클러스터에 반영"이고, 이 프로젝트의 정석은 "Git(`gitops/`)을 고치고 push → ArgoCD가 알아서 apply". 사람이 직접 `apply`한 내용은 ArgoCD `selfHeal`이 곧 되돌려버림. `apply`는 ArgoCD Application 자체를 최초 등록할 때 정도만 직접 씀 |
| `restart` vs `rollout restart` | `kubectl delete pod`는 파드 하나만 지우는 거고 Deployment가 채워넣음. `kubectl rollout restart deployment/x`는 **모든 파드**를 순차적으로 새로 만듦(설정 재로딩 등에 씀) |
| Service 이름 vs Pod 이름 | Pod 이름은 재배포마다 랜덤 문자열이 바뀜(`engame-api-5cb89648d-vm7jq`처럼). 코드/설정에서 참조할 땐 항상 **Service 이름**(`api`, `engame-front`)을 써야 함 — 이 프로젝트의 `nginx.conf`가 `http://api:8080`을 쓰는 이유 |
| `-n engame-dev`를 매번 안 붙이고 싶을 때 | `kubectl config set-context --current --namespace=engame-dev`로 기본 네임스페이스를 지정해두면 이후 `-n` 생략 가능 (단, 다른 네임스페이스 작업할 때 깜빡하고 실수하는 원인이 되기도 하니 주의) |
