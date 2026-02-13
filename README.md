# KubeAI CI/CD

KubeAI 플랫폼 배포를 위한 Helm 차트 및 ArgoCD Application 매니페스트.

## 구조

```
kubeai-cicd/
├── argocd/                    # ArgoCD Application 매니페스트
│   ├── kubeai-app.yaml        # KubeAI 메인 앱 (Helm chart)
│   └── models-app.yaml        # KubeAI Models 앱 (Helm chart)
├── kubeai/                    # KubeAI Helm Chart (v0.21.0)
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   └── charts/
│       └── open-webui-6.4.0.tgz  # Open WebUI 서브차트
├── models/                    # Models Helm Chart (v0.21.0)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       └── models.yaml
├── ImageVolumes/              # 커스텀 이미지/볼륨 리소스
│   ├── Dockerfile
│   └── qwen3-4b-*.yaml
├── kubeai-command.md          # KubeAI 운영 커맨드 참조
└── kubeai-command.txt
```

## 배포 환경

| 항목 | 값 |
|------|-----|
| **클러스터** | minikube (desktop) |
| **네임스페이스** | `kubeai` |
| **GitOps** | ArgoCD (자동 Sync) |
| **Repo** | `https://github.com/bahn1075/kubeai-cicd.git` |
| **Branch** | `main` |

## ArgoCD Applications

### KubeAI (메인)
- **Name:** `kubeai`
- **Source:** `kubeai/` (Helm chart)
- **Namespace:** `kubeai`
- **Sync:** 자동 (prune + selfHeal)

### Models
- **Name:** `kubeai-models`
- **Source:** `models/` (Helm chart)
- **Namespace:** `kubeai`
- **Sync:** 자동 (prune + selfHeal)

## 빠른 시작

### ArgoCD에 등록
```bash
kubectl apply -f argocd/kubeai-app.yaml
kubectl apply -f argocd/models-app.yaml
```

### 상태 확인
```bash
kubectl get applications -n argocd
kubectl get pods -n kubeai
```

## 모델 카탈로그

`models/values.yaml`에서 모델을 활성화/비활성화:

| 모델 | 엔진 | 설명 |
|------|------|------|
| `qwen3-06b-gpu` | OLlama | Qwen3 0.6B (경량) |
| `qwen3-4b-vllm` | VLLM | Qwen3 4B (HuggingFace) |

모델 활성화: `models/values.yaml`에서 `enabled: true` 설정 후 push.

## 워크플로우

1. 로컬에서 수정 (`/app/kubeai-cicd`)
2. `git add && git commit && git push`
3. ArgoCD 자동 감지 → Sync
4. 클러스터에 반영
