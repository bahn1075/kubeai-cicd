# KubeAI 적용을 위한 Command 모음

## 현재 기준

- 로컬 환경: macOS + Minikube
- 현재 설정 기준: Apple Silicon MacBook 환경에서는 GPU 리소스를 직접 pod에 할당하지 않고 CPU fallback 방식으로 동작
- `kubeai/values.yaml`
  - `VLLM` CPU 이미지: `vllm/vllm-openai-cpu:latest-arm64`
  - `OLlama` CPU 이미지: `ollama/ollama:latest`
  - PVC `storageClassName`: `standard`
  - 사내 CA 인증서(`LG CNS`)를 model pod에 자동 주입하도록 Helm 템플릿 반영 완료
- `models/values.yaml`
  - 모든 활성 모델 `resourceProfile`은 `cpu:1`
  - `bge-m3-ollama`는 `minReplicas: 1`
- 현재 Helm release 이름
  - KubeAI 본체: `kubeai`
  - Models: `kubeai-models`

## 기본 확인

```bash
helm version
kubectl config current-context
kubectl config view --minify --output 'jsonpath={..namespace}{"\n"}'
minikube status
helm list -A
```

## KubeAI 설치 / 업데이트

```bash
helm upgrade --install kubeai /Users/cozy/app/kubeai-cicd/kubeai \
  --namespace kubeai \
  --create-namespace \
  -f /Users/cozy/app/kubeai-cicd/kubeai/values.yaml
```

## Models 설치 / 업데이트

주의: models release 이름은 `models`가 아니라 `kubeai-models`를 사용해야 한다.

```bash
helm upgrade --install kubeai-models /Users/cozy/app/kubeai-cicd/models \
  --namespace kubeai \
  -f /Users/cozy/app/kubeai-cicd/models/values.yaml
```

잘못된 예:

```bash
helm upgrade --install models /Users/cozy/app/kubeai-cicd/models \
  --namespace kubeai \
  -f /Users/cozy/app/kubeai-cicd/models/values.yaml
```

위 명령은 기존 `kubeai-models` release가 소유한 `Model` 리소스와 충돌할 수 있다.

## 상태 확인

### Helm release 확인

```bash
helm list -A
helm list -n kubeai
```

### 전체 pod 확인

```bash
kubectl get pods -n kubeai -o wide
```

### service 확인

```bash
kubectl get svc -n kubeai -o wide
```

현재 예시:

- `open-webui` `LoadBalancer`: `10.101.92.100`
- `open-webui` `NodePort`: `31027`

### model 확인

```bash
kubectl get models -n kubeai
kubectl get model bge-m3-ollama -n kubeai -o yaml
```

## Open WebUI 접속

### minikube tunnel 사용 시

터미널 1개를 별도로 열고:

```bash
minikube tunnel
```

브라우저 접속:

```text
http://10.101.92.100
```

### NodePort로 접속

```text
http://192.168.105.3:31027
```

### Minikube가 알려주는 URL 확인

```bash
minikube service open-webui -n kubeai --url
```

## 로그 확인

### kubeai 컨트롤러 로그

```bash
kubectl logs -n kubeai deploy/kubeai --tail=100
```

### open-webui 로그

```bash
kubectl logs -n kubeai open-webui-0 --tail=100
kubectl logs -n kubeai open-webui-0 -f
```

### model pod 로그

```bash
kubectl logs -n kubeai -l model=bge-m3-ollama --tail=100 --all-containers=true
kubectl logs -n kubeai -l model=bge-m3-ollama -f --all-containers=true
```

## 모델 활성화 조절

`/Users/cozy/app/kubeai-cicd/models/values.yaml`에서 `enabled`, `minReplicas` 값을 조절한 뒤 다시 upgrade 한다.

```bash
helm upgrade --install kubeai-models /Users/cozy/app/kubeai-cicd/models \
  --namespace kubeai \
  -f /Users/cozy/app/kubeai-cicd/models/values.yaml
```

삭제:

```bash
helm uninstall kubeai-models -n kubeai
```

rollback:

```bash
helm rollback kubeai-models 7 -n kubeai
```

## 인증서 관련

현재 차트에는 `LG CNS` 사내 CA 인증서가 포함되어 있으며, model pod 기동 시 init container가 기본 CA 번들에 인증서를 합쳐서 `/etc/ssl/certs/ca-certificates.crt`에 마운트한다.

### ConfigMap 확인

```bash
kubectl get configmap lgcns-custom-ca -n kubeai -o yaml
```

### model pod 내부 CA 파일 확인

```bash
kubectl exec -n kubeai $(kubectl get pod -n kubeai -l model=bge-m3-ollama -o jsonpath='{.items[0].metadata.name}') -- \
  sh -lc 'tail -n 20 /etc/ssl/certs/ca-certificates.crt'
```

### 인증서 오류 발생 시 확인 포인트

```bash
kubectl logs -n kubeai -l model=bge-m3-ollama --tail=200 --all-containers=true | grep -i x509
kubectl get configmap lgcns-custom-ca -n kubeai
```

## PVC 확인

```bash
kubectl get pvc -n kubeai
```

현재 설정:

- `kubeai-hf-cache`
- `kubeai-ollama-cache`
- `open-webui`

모두 `Bound` 상태여야 정상이다.

## 재배포 순서

설정 변경 후 일반적인 재반영 순서:

```bash
helm upgrade --install kubeai /Users/cozy/app/kubeai-cicd/kubeai \
  -n kubeai \
  -f /Users/cozy/app/kubeai-cicd/kubeai/values.yaml

helm upgrade --install kubeai-models /Users/cozy/app/kubeai-cicd/models \
  -n kubeai \
  -f /Users/cozy/app/kubeai-cicd/models/values.yaml

kubectl get pods -n kubeai -o wide
```

## 삭제

```bash
helm uninstall kubeai-models -n kubeai
helm uninstall kubeai -n kubeai
kubectl delete namespace kubeai
```

## 자주 쓰는 절대 경로

- KubeAI chart: `/Users/cozy/app/kubeai-cicd/kubeai`
- KubeAI values: `/Users/cozy/app/kubeai-cicd/kubeai/values.yaml`
- Models chart: `/Users/cozy/app/kubeai-cicd/models`
- Models values: `/Users/cozy/app/kubeai-cicd/models/values.yaml`
- 운영 문서(txt): `/Users/cozy/app/kubeai-cicd/kubeai-command.txt`
- 운영 문서(md): `/Users/cozy/app/kubeai-cicd/kubeai-command.md`

## 참고

- Mac Minikube 환경에서는 NVIDIA/AMD GPU 방식처럼 pod 단위 GPU 독점 할당이 아니라 CPU fallback 기준으로 보는 것이 안전하다.
- `open-webui`는 초기 실행 시 내부 다운로드/초기화 때문에 바로 응답하지 않을 수 있다.
- `bge-m3-ollama`는 현재 정상 기동 확인 완료.
