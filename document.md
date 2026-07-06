# directory 
my-eks-project/
├── bootstrap/              # [초기화] S3, DynamoDB 등 TF 상태 관리 리소스 생성
├── terraform/              # [인프라 코드]
│   ├── modules/            # 재사용 가능한 인프라 모듈 (vpc, eks, iam, ecr)
│   └── environments/       # 환경별 실제 배포 설정
│       ├── dev/            # 개발 환경 (v2.0 등 버전 관리)
│       └── prod/           # 운영 환경
├── services/               # [애플리케이션 소스]
│   ├── api-server/         # Spring Boot 소스
│   └── web-client/         # React 소스
├── gitops/                 # [배포 매니페스트] ArgoCD가 참조할 K8s 설정
│   ├── base/               # 공통 설정
│   └── overlays/           # 환경별 변경점 (dev, prod)
├── .github/workflows/      # [CI/CD 파이프라인] 빌드, 테스트, Docker Build, ECR Push
└── docs/                   # 프로젝트 설계 문서, 아키텍처 다이어그램
