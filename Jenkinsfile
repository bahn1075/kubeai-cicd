pipeline {
    agent any

    parameters {
        string(
            name: 'PROJECT_NAME',
            defaultValue: 'test1',
            description: 'project name (main branch에서 분기될 branch명으로 사용)',
            trim: true
        )
        choice(
            name: 'SERVICE_TYPE',
            choices: ['TextGeneration', 'TextEmbedding', 'Reranking', 'SpeechToText'],
            description: 'service type'
        )
        choice(
            name: 'LLM_SERVE',
            choices: ['Ollama', 'vLLM'],
            description: 'LLM serve'
        )
        choice(
            name: 'LLM_MODEL',
            choices: [
                'ollama://qwen3:0.6b',
                'ollama://qwen3:4b',
                'ollama://qwen3:8b',
                'ollama://qwen3:14b',
                'ollama://qwen3:32b',
                'ollama://llama3.1:8b',
                'ollama://llama3.1:70b',
                'ollama://gemma3:4b',
                'ollama://gemma3:12b',
                'ollama://gemma3:27b',
                'ollama://deepseek-r1:7b',
                'ollama://deepseek-r1:14b',
                'ollama://mistral:7b',
                'ollama://phi4:14b',
                'hf://Qwen/Qwen3-0.6B',
                'hf://Qwen/Qwen3-4B',
                'hf://Qwen/Qwen3-8B',
                'hf://Qwen/Qwen3-14B',
                'hf://Qwen/Qwen3-32B',
                'hf://meta-llama/Llama-3.1-8B-Instruct',
                'hf://meta-llama/Llama-3.1-70B-Instruct',
                'hf://google/gemma-3-4b-it',
                'hf://google/gemma-3-12b-it',
                'hf://google/gemma-3-27b-it',
                'hf://deepseek-ai/DeepSeek-R1-Distill-Qwen-7B',
                'hf://deepseek-ai/DeepSeek-R1-Distill-Qwen-14B',
                'hf://mistralai/Mistral-7B-Instruct-v0.3',
                'hf://microsoft/phi-4'
            ],
            description: 'LLM model (정확한 모델명을 입력해야 합니다)'
        )
    }

    environment {
        REPO_URL = 'https://github.com/bahn1075/kubeai-cicd.git'
        VALUES_FILE = 'models/values.yaml'
        GIT_CREDENTIALS_ID = 'github'
    }

    stages {
        stage('Validate Parameters') {
            steps {
                script {
                    if (!params.PROJECT_NAME?.trim()) {
                        error "PROJECT_NAME은 필수 입력값입니다."
                    }
                    // serve 타입과 모델 URL prefix 일관성 검증
                    if (params.LLM_SERVE == 'Ollama' && !params.LLM_MODEL.startsWith('ollama://')) {
                        error "Ollama serve 타입에는 ollama:// 모델을 선택해야 합니다."
                    }
                    if (params.LLM_SERVE == 'vLLM' && !params.LLM_MODEL.startsWith('hf://')) {
                        error "vLLM serve 타입에는 hf:// 모델을 선택해야 합니다."
                    }
                    echo "✅ 파라미터 검증 완료"
                    echo "  - Project: ${params.PROJECT_NAME}"
                    echo "  - Service: ${params.SERVICE_TYPE}"
                    echo "  - Serve:   ${params.LLM_SERVE}"
                    echo "  - Model:   ${params.LLM_MODEL}"
                }
            }
        }

        stage('Checkout & Branch') {
            steps {
                script {
                    // main 체크아웃
                    git branch: 'main', credentialsId: env.GIT_CREDENTIALS_ID, url: env.REPO_URL

                    // 프로젝트명 브랜치 생성 (이미 존재하면 체크아웃)
                    def branchName = params.PROJECT_NAME.trim()
                    def branchExists = sh(
                        script: "git ls-remote --heads origin ${branchName} | wc -l",
                        returnStdout: true
                    ).trim()

                    if (branchExists == '0') {
                        sh "git checkout -b ${branchName}"
                        echo "🌿 새 브랜치 생성: ${branchName}"
                    } else {
                        sh "git fetch origin ${branchName}"
                        sh "git checkout ${branchName}"
                        sh "git merge origin/main --no-edit || true"
                        echo "🔄 기존 브랜치 체크아웃: ${branchName} (main 머지 완료)"
                    }
                }
            }
        }

        stage('Generate Model Config') {
            steps {
                script {
                    def projectName = params.PROJECT_NAME.trim()
                    def serviceType = params.SERVICE_TYPE
                    def llmServe = params.LLM_SERVE
                    def llmModel = params.LLM_MODEL
                    def modelBlock = ""

                    if (llmServe == 'Ollama') {
                        modelBlock = """
  ${projectName}:
    enabled: true
    features: ["${serviceType}"]
    url: "${llmModel}"
    engine: OLlama
    env:
      OLLAMA_KEEP_ALIVE: "1"
      OLLAMA_MAX_LOADED_MODELS: "2"
      OLLAMA_FLASH_ATTENTION: "true"
    minReplicas: 1
    resourceProfile: amd-gpu-rx9070xt:1"""
                    } else {
                        // vLLM
                        modelBlock = """
  ${projectName}:
    enabled: true
    features: [${serviceType}]
    url: ${llmModel}
    engine: VLLM
    env:
      HIP_FORCE_DEV_KERNARG: "1"
      NCCL_MIN_NCHANNELS: "112"
      TORCH_BLAS_PREFER_HIPBLASLT: "1"
      VLLM_USE_TRITON_FLASH_ATTN: "0"
      VLLM_FP8_PADDING: "0"
    args:
      - --trust-remote-code
      - --max-model-len=8192
      - --max-num-batched-tokens=4096
      - --max-num-seqs=64
      - --tensor-parallel-size=1
    minReplicas: 1
    resourceProfile: amd-gpu-rx9070xt:1
    targetRequests: 64"""
                    }

                    // values.yaml에 모델 블럭 추가 (중복 방지)
                    def valuesContent = readFile(env.VALUES_FILE)

                    if (valuesContent.contains("${projectName}:")) {
                        echo "⚠️ 프로젝트 '${projectName}' 블럭이 이미 존재합니다. enabled를 true로 업데이트합니다."
                        // 기존 블럭의 enabled를 true로 변경
                        valuesContent = valuesContent.replaceAll(
                            "(${projectName}:\\s*\\n\\s*enabled:\\s*)false",
                            "\$1true"
                        )
                        writeFile file: env.VALUES_FILE, text: valuesContent
                    } else {
                        // 새 블럭 append
                        sh "echo '${modelBlock}' >> ${env.VALUES_FILE}"
                        echo "✅ 새 모델 블럭 추가 완료: ${projectName}"
                    }

                    echo "\n📄 현재 values.yaml:"
                    sh "cat ${env.VALUES_FILE}"
                }
            }
        }

        stage('Commit & Push') {
            steps {
                script {
                    def branchName = params.PROJECT_NAME.trim()
                    def commitMsg = "feat(${branchName}): deploy ${params.LLM_SERVE} model ${params.LLM_MODEL} [${params.SERVICE_TYPE}]"

                    withCredentials([usernamePassword(credentialsId: env.GIT_CREDENTIALS_ID, usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                        withEnv(["BRANCH_NAME=${branchName}", "COMMIT_MSG=${commitMsg}"]) {
                            sh '''
                                set -e
                                git config user.email "jenkins@kubeai-cicd"
                                git config user.name "Jenkins Pipeline"
                                git remote set-url origin "$REPO_URL"
                                git add -A
                                if git diff --cached --quiet; then
                                    echo 'No changes to commit'
                                else
                                    git commit -m "$COMMIT_MSG"

                                    # Jenkins credential username이 이메일인 경우 user 부분만 추출
                                    PUSH_USER="${GIT_USERNAME%@*}"
                                    if [ -z "$PUSH_USER" ]; then
                                        PUSH_USER="$GIT_USERNAME"
                                    fi

                                    if ! git -c credential.username="$PUSH_USER" -c credential.helper='!f() { echo "password=$GIT_PASSWORD"; }; f' push origin "$BRANCH_NAME"; then
                                        echo "❌ Git push 실패: Jenkins credential 'github' 권한을 확인하세요."
                                        echo "   - Username: GitHub 로그인 ID (이메일 대신 계정명 권장)"
                                        echo "   - Password: GitHub PAT"
                                        echo "   - PAT 권한: repo(클래식) 또는 Contents: Read and write(fine-grained)"
                                        exit 1
                                    fi
                                fi
                            '''
                        }
                    }
                    echo "🚀 Push 완료: branch '${branchName}'"
                }
            }
        }
    }

    post {
        success {
            echo """
            ╔══════════════════════════════════════════╗
            ║     ✅ Model 배포 파이프라인 성공!       ║
            ╠══════════════════════════════════════════╣
            ║  Project : ${params.PROJECT_NAME}        
            ║  Service : ${params.SERVICE_TYPE}        
            ║  Serve   : ${params.LLM_SERVE}           
            ║  Model   : ${params.LLM_MODEL}           
            ║  Branch  : ${params.PROJECT_NAME}        
            ╚══════════════════════════════════════════╝
            """
        }
        failure {
            echo "❌ 파이프라인 실패! 로그를 확인하세요."
        }
    }
}
