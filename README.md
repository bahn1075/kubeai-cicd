# KubeAI CI/CD

Jenkins 자동화 파이프라인과 ArgoCD GitOps를 활용한 KubeAI 플랫폼 배포 시스템.

## 🏗️ 아키텍처

```
                    ┌──────────────┐
                    │   Jenkins    │
                    │  Pipelines   │
                    └──────┬───────┘
                           │ Git Push
                           ▼
                    ┌──────────────┐
                    │   GitHub     │
                    │ (main branch)│
                    └──────┬───────┘
                           │ Sync
                           ▼
                    ┌──────────────┐
                    │   ArgoCD     │
                    │  (GitOps)    │
                    └──────┬───────┘
                           │ Deploy
                           ▼
              ┌────────────┴────────────┐
              ▼                         ▼
        ┌──────────┐             ┌──────────┐
        │  KubeAI  │             │   Kong   │
        │  Models  │◄────────────│ Gateway  │
        └──────────┘             └──────────┘
```

## 📁 디렉토리 구조

```
kubeai-cicd/
├── Jenkinsfile                # 프로젝트 생성 파이프라인
├── Jenkinsfile.delete         # 프로젝트 삭제 파이프라인
├── argocd/                    # ArgoCD Application 매니페스트
│   ├── kubeai-app.yaml        # KubeAI 메인 앱 (Helm chart)
│   └── models-app.yaml        # KubeAI Models 앱 (Helm chart)
├── kong/                      # Kong API Gateway 설정
│   ├── application.yaml       # Kong Application
│   ├── values.yaml            # Kong Helm values
│   └── services/              # Kong Service 정의
│       └── .gitkeep           # 디렉토리 보호
├── kubeai/                    # KubeAI Helm Chart (v0.21.0)
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-*.yaml          # 환경별 설정 (EKS, GKE, AMD GPU 등)
│   └── templates/             # Kubernetes 리소스 템플릿
├── models/                    # Models Helm Chart (v0.21.0)
│   ├── Chart.yaml
│   ├── values.yaml            # 모델 카탈로그
│   └── templates/
│       └── models.yaml
├── ImageVolumes/              # 커스텀 이미지/볼륨 리소스
└── kubeai-command.md          # KubeAI 운영 커맨드 참조
```

## 🚀 배포 환경

| 항목 | 값 |
|------|-----|
| **클러스터** | Kubernetes (Minikube/EKS/GKE) |
| **네임스페이스** | `kubeai` |
| **GitOps** | ArgoCD (자동 Sync) |
| **CI/CD** | Jenkins Pipeline |
| **API Gateway** | Kong |
| **Repo** | `https://github.com/bahn1075/kubeai-cicd.git` |
| **Branch** | `main` |

## 🔧 Jenkins 파이프라인

### 1. 프로젝트 생성 (`Jenkinsfile`)

새로운 AI 모델 프로젝트를 생성하고 배포합니다.

**파라미터:**
- `PROJECT_NAME`: 프로젝트 이름 (브랜치명으로 사용)
- `SERVICE_TYPE`: TextGeneration, TextEmbedding, Reranking, SpeechToText
- `LLM_SERVE`: ollama, vLLM
- `LLM_MODEL`: 모델 선택 (LLM_SERVE에 따라 동적 변경)

**수행 작업:**
1. `PROJECT_NAME` 브랜치 생성
2. `kong/services/{PROJECT_NAME}.yaml` 생성 (Kong Service 정의)
3. `models/values.yaml`에 모델 설정 추가
4. PR 생성 → main 브랜치로 머지 대기

**실행 예시:**
```groovy
PROJECT_NAME: bge-m3
SERVICE_TYPE: TextEmbedding
LLM_SERVE: ollama
LLM_MODEL: ollama://bge-m3
```

### 2. 프로젝트 삭제 (`Jenkinsfile.delete`)

기존 프로젝트 리소스를 삭제합니다.

**파라미터:**
- `PROJECT_NAME`: 삭제할 프로젝트 이름

**수행 작업:**
1. `delete-{PROJECT_NAME}` 브랜치 생성
2. `kong/services/{PROJECT_NAME}.yaml` 삭제
3. `models/values.yaml`에서 모델 블럭 제거
4. 원본 브랜치 삭제
5. PR 생성 → main 브랜치로 머지 대기
6. ⚠️ `kong/services/` 디렉토리 보호 (`.gitkeep` 자동 생성)

## 🎯 ArgoCD Applications

### KubeAI (메인)
- **Name:** `kubeai`
- **Source:** `kubeai/` (Helm chart)
- **Namespace:** `kubeai`
- **Sync:** 자동 (prune + selfHeal)
- **주요 컴포넌트:** LLM Serving, Autoscaler, Open WebUI

### Models
- **Name:** `kubeai-models`
- **Source:** `models/` (Helm chart)
- **Namespace:** `kubeai`
- **Sync:** 자동 (prune + selfHeal)
- **역할:** AI 모델 카탈로그 관리

### Kong Gateway
- **Source:** `kong/application.yaml`
- **역할:** API Gateway, 라우팅, 인증

## 📊 모델 카탈로그

현재 지원하는 모델 (`models/values.yaml`):

| 모델 | 엔진 | URL | 설명 |
|------|------|-----|------|
| `qwen3-06b-gpu` | OLlama | `ollama://qwen3:0.6b` | Qwen3 0.6B (경량) |
| `qwen3-4b-vllm` | VLLM | `hf://Qwen/Qwen3-4B` | Qwen3 4B (HuggingFace) |

**지원 LLM 서빙 엔진:**
- **OLlama**: `ollama://` prefix
- **vLLM**: `hf://` prefix (HuggingFace)

## 🔄 워크플로우

### 자동화 워크플로우 (Jenkins)

```
┌─────────────────┐
│ Jenkins 실행    │
│ (Create/Delete) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 브랜치 생성     │
│ 파일 수정       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Pull Request    │
│ 생성            │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PR 승인 & Merge │
│ → main branch   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ ArgoCD Sync     │
│ 자동 감지       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Kubernetes      │
│ 리소스 배포     │
└─────────────────┘
```

### 수동 워크플로우

1. 로컬에서 직접 수정 (`/app/kubeai-cicd`)
2. `git add && git commit && git push`
3. ArgoCD 자동 감지 → Sync
4. 클러스터에 반영

## 📝 주요 기능

### 자동화된 프로젝트 관리
- ✅ Jenkins로 모델 프로젝트 자동 생성/삭제
- ✅ Kong Service 자동 구성
- ✅ Models 카탈로그 자동 업데이트
- ✅ Pull Request 기반 변경 관리
- ✅ 디렉토리 보호 (`.gitkeep` 자동 관리)

### GitOps 기반 배포
- ✅ ArgoCD 자동 Sync (prune + selfHeal)
- ✅ Git을 단일 진실 공급원(Single Source of Truth)으로 사용
- ✅ 선언적 설정 관리

### 다양한 환경 지원
- ✅ AMD GPU (RX 9070 XT)
- ✅ NVIDIA GPU
- ✅ AWS EKS
- ✅ GCP GKE
- ✅ Minikube (로컬 개발)

## 🔒 보안 & 인증

### GitHub Credentials
Jenkins에서 GitHub 인증을 위해 `github` credential 필요:
- **Credential ID**: `github`
- **Type**: Username with password
- **Username**: GitHub username or email
- **Password**: GitHub Personal Access Token (PAT)

**필요 권한:**
- `repo` (전체 저장소 액세스)
- `workflow` (GitHub Actions 워크플로우)

## 🐛 문제 해결

### kong/services 디렉토리 삭제 문제
**증상:** 모든 Kong 서비스 파일을 삭제하면 `kong/services/` 디렉토리가 사라져 ArgoCD 에러 발생

**해결:** `.gitkeep` 파일로 디렉토리 보호
- 파이프라인이 자동으로 `.gitkeep` 생성
- Git이 빈 디렉토리를 추적하도록 보장

### Jenkins PR 생성 실패
**증상:** GitHub API 호출 시 인증 실패

**해결:** 
1. GitHub PAT 재생성 (필요 권한 확인)
2. Jenkins Credential 업데이트
3. 파이프라인 재실행

### ArgoCD 자동 Prune 실패 (Model 삭제 안됨)
**증상:** 
- Delete 파이프라인 실행 후 모델 블럭이 `values.yaml`에서 삭제됨
- ArgoCD가 변경사항을 감지하고 Sync 수행
- 하지만 Model Pod가 자동으로 삭제되지 않음
- Warning 발생 후, 수동으로 Prune 체크 → Sync해야만 삭제됨

**원인:** 
- `Model`은 Custom Resource (CR)이며, ArgoCD는 기본적으로 CR을 자동 prune하지 않음
- 안전성을 위한 설계 (CR 삭제가 연관 리소스에 영향을 줄 수 있음)

**해결:** 
ArgoCD Application manifest에 `PruneLast=true` syncOption 추가 (이미 적용됨):
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - PruneLast=true  # CR을 마지막에 prune
    - RespectIgnoreDifferences=true
```

**적용 방법:**
```bash
kubectl apply -f argocd/models-app.yaml
# 또는 ArgoCD UI에서 Application 재생성
```

## 📚 참고 문서

- [KubeAI 공식 문서](https://www.kubeai.org/)
- [ArgoCD 문서](https://argo-cd.readthedocs.io/)
- [Kong Gateway 문서](https://docs.konghq.com/)
- [Jenkins Pipeline 문서](https://www.jenkins.io/doc/book/pipeline/)

## 📄 라이선스

MIT License

---

**Last Updated:** 2026-03-09

## 🛠️ 빠른 시작

### ArgoCD에 등록
```bash
kubectl apply -f argocd/kubeai-app.yaml
kubectl apply -f argocd/models-app.yaml
kubectl apply -f kong/application.yaml
```

### 상태 확인
```bash
# ArgoCD Applications
kubectl get applications -n argocd

# KubeAI Pods
kubectl get pods -n kubeai

# Kong Services
kubectl get svc -n kong
```

### Jenkins Pipeline 실행
1. Jenkins UI 접속
2. `Jenkinsfile` 또는 `Jenkinsfile.delete` 파이프라인 선택
3. 파라미터 입력 후 빌드
4. GitHub에서 생성된 PR 확인 및 머지
