properties([
    parameters([
        string(
            name: 'PROJECT_NAME',
            defaultValue: 'test1',
            description: 'project name (main branch에서 분기될 branch명으로 사용)',
            trim: true
        ),
        choice(
            name: 'SERVICE_TYPE',
            choices: ['TextGeneration', 'TextEmbedding', 'Reranking', 'SpeechToText'],
            description: 'service type'
        ),
        choice(
            name: 'LLM_SERVE',
            choices: ['ollama', 'vLLM'],
            description: 'LLM serve'
        ),
        [
            $class: 'CascadeChoiceParameter',
            choiceType: 'PT_SINGLE_SELECT',
            description: 'LLM model (LLM_SERVE 선택값에 따라 자동 변경)',
            filterLength: 1,
            filterable: false,
            name: 'LLM_MODEL',
            randomName: 'llm-model-choice',
            referencedParameters: 'LLM_SERVE',
            script: [
                $class: 'GroovyScript',
                fallbackScript: [
                    classpath: [],
                    sandbox: true,
                    script: "return ['LLM_MODEL 목록을 불러오지 못했습니다.']"
                ],
                script: [
                    classpath: [],
                    sandbox: true,
                    script: """
                        if (LLM_SERVE == 'ollama') {
                            return [
                                'ollama://exaone3.5',
                                'ollama://qwen3:4b',
                                'ollama://qwen3:8b',
                                'ollama://qwen3:14b'
                            ]
                        }
                        if (LLM_SERVE == 'vLLM') {
                            return [
                                'hf://Qwen/Qwen3-0.6B',
                                'hf://Qwen/Qwen3-4B',
                                'hf://Qwen/Qwen3-8B',
                                'hf://Qwen/Qwen3-14B'
                            ]
                        }
                        return ['먼저 LLM_SERVE를 선택하세요.']
                    """
                ]
            ]
        ]
    ])
])

pipeline {
    agent any

    environment {
        REPO_URL = 'https://github.com/bahn1075/kubeai-cicd.git'
        REPO_OWNER = 'bahn1075'
        REPO_NAME = 'kubeai-cicd'
        BASE_BRANCH = 'main'
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
                    if (params.LLM_SERVE == 'ollama' && !params.LLM_MODEL.startsWith('ollama://')) {
                        error "ollama serve 타입에는 ollama:// 모델을 선택해야 합니다."
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

                    if (llmServe == 'ollama') {
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
                        echo "⚠️ 프로젝트 '${projectName}' 블럭이 이미 존재합니다. 입력값 기준으로 전체 덮어씁니다."
                        // catalog 하위의 동일 project 블럭 전체를 새 modelBlock으로 교체
                        def escapedProject = java.util.regex.Pattern.quote(projectName)
                        def blockPattern = "(?ms)^  ${escapedProject}:\\n(?:    .*\\n|\\n)*?(?=^  [^\\s].*:\\n|\\z)"
                        def normalizedBlock = modelBlock.startsWith("\n") ? modelBlock.substring(1) : modelBlock
                        valuesContent = valuesContent.replaceFirst(blockPattern, normalizedBlock + "\n")
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

        stage('Create Merge Request') {
            steps {
                script {
                    def branchName = params.PROJECT_NAME.trim()
                    if (branchName == env.BASE_BRANCH) {
                        echo "ℹ️ PR 생성 스킵: source branch가 '${env.BASE_BRANCH}'입니다."
                        return
                    }

                    withCredentials([usernamePassword(credentialsId: env.GIT_CREDENTIALS_ID, usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                        withEnv(["BRANCH_NAME=${branchName}"]) {
                            sh '''
                                set -eu
                                API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME"
                                AUTH_HEADER="Authorization: Bearer $GIT_PASSWORD"
                                ACCEPT_HEADER="Accept: application/vnd.github+json"
                                API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"

                                extract_html_url() {
                                  sed -n 's/.*"html_url"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p' "$1" | head -n 1
                                }

                                # 이미 열려 있는 PR이 있으면 재사용
                                EXISTING_PR_RESPONSE=$(mktemp)
                                EXISTING_HTTP_CODE=$(curl -sS -o "$EXISTING_PR_RESPONSE" -w "%{http_code}" \
                                  -H "$AUTH_HEADER" \
                                  -H "$ACCEPT_HEADER" \
                                  -H "$API_VERSION_HEADER" \
                                  "$API_URL/pulls?state=open&head=$REPO_OWNER:$BRANCH_NAME&base=$BASE_BRANCH")
                                if [ "$EXISTING_HTTP_CODE" -ge 400 ]; then
                                    echo "❌ 기존 PR 조회 실패 (HTTP $EXISTING_HTTP_CODE)"
                                    cat "$EXISTING_PR_RESPONSE"
                                    rm -f "$EXISTING_PR_RESPONSE"
                                    exit 1
                                fi
                                EXISTING_PR_URL=$(extract_html_url "$EXISTING_PR_RESPONSE")
                                rm -f "$EXISTING_PR_RESPONSE"

                                if [ -n "$EXISTING_PR_URL" ]; then
                                    echo "🔁 기존 PR 재사용: $EXISTING_PR_URL"
                                    exit 0
                                fi

                                PAYLOAD="{\\"title\\":\\"Merge $BRANCH_NAME into $BASE_BRANCH\\",\\"head\\":\\"$BRANCH_NAME\\",\\"base\\":\\"$BASE_BRANCH\\",\\"body\\":\\"Auto-created by Jenkins pipeline.\\"}"
                                CREATED_PR_RESPONSE=$(mktemp)
                                CREATED_HTTP_CODE=$(curl -sS -o "$CREATED_PR_RESPONSE" -w "%{http_code}" -X POST \
                                  -H "$AUTH_HEADER" \
                                  -H "$ACCEPT_HEADER" \
                                  -H "$API_VERSION_HEADER" \
                                  "$API_URL/pulls" \
                                  -d "$PAYLOAD" \
                                  )
                                if [ "$CREATED_HTTP_CODE" -ge 400 ]; then
                                    echo "❌ PR 생성 실패 (HTTP $CREATED_HTTP_CODE)"
                                    cat "$CREATED_PR_RESPONSE"
                                    rm -f "$CREATED_PR_RESPONSE"
                                    exit 1
                                fi
                                CREATED_PR_URL=$(extract_html_url "$CREATED_PR_RESPONSE")
                                rm -f "$CREATED_PR_RESPONSE"

                                if [ -z "$CREATED_PR_URL" ]; then
                                    echo "❌ PR 생성 응답에서 html_url을 찾지 못했습니다. token 권한과 API 응답을 확인하세요."
                                    exit 1
                                fi

                                echo "✅ PR 생성 완료: $CREATED_PR_URL"
                            '''
                        }
                    }
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
