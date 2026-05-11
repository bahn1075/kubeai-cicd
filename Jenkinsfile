properties([
    parameters([
        string(
            name: 'PROJECT_NAME',
            defaultValue: 'test1',
            description: 'project name (desktop branch에서 분기될 branch명으로 사용)',
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
                                'ollama://bge-m3',
                                'ollama://exaone3.5',
                                'ollama://qwen3.5:9b'
                            ]
                        }
                        if (LLM_SERVE == 'vLLM') {
                            return [
                                'hf://Qwen/Qwen3.5-9B-Base'
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
        BASE_BRANCH = 'desktop'
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
                    // base branch 체크아웃
                    git branch: env.BASE_BRANCH, credentialsId: env.GIT_CREDENTIALS_ID, url: env.REPO_URL

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
                        sh "git merge origin/${env.BASE_BRANCH} --no-edit || true"
                        echo "🔄 기존 브랜치 체크아웃: ${branchName} (${env.BASE_BRANCH} 머지 완료)"
                    }
                }
            }
        }

        stage('Generate Kong Service') {
            steps {
                script {
                    def projectName = params.PROJECT_NAME.trim()
                    def normalizedProjectName = projectName
                        .toLowerCase()
                        .replaceAll('[^a-z0-9-]', '-')
                        .replaceAll('-+', '-')
                        .replaceAll('(^-|-$)', '')
                    def serviceFile = "kong/services/${projectName}.yaml"
                    def valuesContent = readFile(env.VALUES_FILE)
                    def modelConfigMatches = []
                    def currentModelName = null

                    valuesContent.readLines().each { line ->
                        if (line.startsWith('  ') && !line.startsWith('    ') && line.endsWith(':')) {
                            currentModelName = line.trim().replaceFirst(':$', '')
                        } else if (currentModelName && line.trim().startsWith('url:')) {
                            def definedModelUrl = line.trim().substring('url:'.length()).trim()
                            if ((definedModelUrl.startsWith('"') && definedModelUrl.endsWith('"')) ||
                                (definedModelUrl.startsWith("'") && definedModelUrl.endsWith("'"))) {
                                definedModelUrl = definedModelUrl.substring(1, definedModelUrl.length() - 1)
                            }

                            if (definedModelUrl == params.LLM_MODEL || definedModelUrl.startsWith("${params.LLM_MODEL}:")) {
                                modelConfigMatches << currentModelName
                            }
                        }
                    }

                    if (modelConfigMatches.size() == 0) {
                        error "❌ ${env.VALUES_FILE}에서 선택한 모델 '${params.LLM_MODEL}'에 해당하는 catalog 항목을 찾지 못했습니다."
                    }
                    if (modelConfigMatches.size() > 1) {
                        error "❌ 선택한 모델 '${params.LLM_MODEL}'에 해당하는 catalog 항목이 여러 개입니다: ${modelConfigMatches.join(', ')}"
                    }

                    def modelConfigName = modelConfigMatches[0]

                    def kongServiceYaml = """apiVersion: v1
kind: Service
metadata:
  name: ${normalizedProjectName}
  namespace: kubeai
spec:
  selector:
    model: ${modelConfigName}
  ports:
    - name: http
      port: 8000
      targetPort: 8000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${normalizedProjectName}
  namespace: kubeai
  annotations:
    konghq.com/strip-path: "true"
spec:
  ingressClassName: kong
  rules:
    - http:
        paths:
          - path: /${projectName}
            pathType: Prefix
            backend:
              service:
                name: ${normalizedProjectName}
                port:
                  number: 8000
"""

                    // Kong 서비스 파일 생성 또는 덮어쓰기
                    writeFile file: serviceFile, text: kongServiceYaml
                    echo "✅ Kong 서비스 파일 생성 완료: ${serviceFile}"
                    echo "  - Project Service: ${normalizedProjectName}"
                    echo "  - Target Model: ${modelConfigName}"
                    
                    echo "\n📄 생성된 Kong Service:"
                    sh "cat ${serviceFile}"
                }
            }
        }

        stage('Commit & Push') {
            steps {
                script {
                    def branchName = params.PROJECT_NAME.trim()
                    def commitMsg = "feat(${branchName}): configure Kong service for ${params.LLM_MODEL}"

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
            ║     ✅ Kong 서비스 생성 완료!            ║
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
