import java.text.SimpleDateFormat

def TODAY = (new SimpleDateFormat("yyMMddHHmm")).format(new Date())

pipeline {
    agent any

    environment {
        VERSION = "${TODAY}_${BUILD_ID}"
    }
    
    stages {
        stage('Checkout') {
            steps {
                // Get some code from a GitHub repository
                git (branch: 'master'
                    , url:'https://github.com/bookinfo-jenkins-project/details.git')
                dir('/var/lib/jenkins/subWorkspace/bookinfo/config'){
                    git branch: 'master', url:'https://github.com/bookinfo-jenkins-project/config.git'
                }
            }
        }
        stage('Build'){
            steps{
                sh '''
                    echo \'Build details\'
                    echo "Version: ${VERSION}"
                '''
                script {
                    v1DockImage = docker.build("winterash2/examples-bookinfo-details-v1:${VERSION}", "--pull -t winterash2/examples-bookinfo-details-v1:${VERSION} -t winterash2/examples-bookinfo-details-v1:latest --build-arg service_version=v1 .")
                    v2DockImage = docker.build("winterash2/examples-bookinfo-details-v2:${VERSION}", "--pull -t winterash2/examples-bookinfo-details-v2:${VERSION} -t winterash2/examples-bookinfo-details-v2:latest --build-arg service_version=v2 --build-arg enable_external_book_service=true .")
                }
            }
        }
        stage('Docker Image Push') {
            steps {
                    script {
                    docker.withRegistry('', 'DockerHub_winterash2') {
                        v1DockImage.push()
                    }
                    docker.withRegistry('', 'DockerHub_winterash2') {
                        v2DockImage.push()
                    }
                }
            }
        }
        stage('Config-Repo PUSH') {
            environment {
                GITHUB_ACCESS_TOKEN = credentials('github-access-token')
            }
            steps {
                dir('/var/lib/jenkins/subWorkspace/bookinfo/config'){
                sh '''
                    sed -i "s/examples-bookinfo-details-v1:.*/examples-bookinfo-details-v1:${VERSION}/g" bookinfo/bookinfo-details.yaml
                    sed -i "s/examples-bookinfo-details-v2:.*/examples-bookinfo-details-v2:${VERSION}/g" bookinfo/bookinfo-details.yaml
                    git add bookinfo/bookinfo-details.yaml
                    git commit -m "[UPDATE] guestbook image tag - ${VERSION} (by jenkins)"
                    git push "https://winterash2:${GITHUB_ACCESS_TOKEN}@github.com/bookinfo-jenkins-project/config.git"
                '''
                }
            }
        }
        stage('ArgoCD Sync') {
            environment {
                ARGOCD_API_TOKEN = credentials('argocd-api-token')
            }
            steps {
                sh '''
                TOKEN="${ARGOCD_API_TOKEN}"
                PAYLOAD='{"prune": true}'
                curl -v -k -XPOST \
                    -H "Authorization: Bearer ${TOKEN}" \
                    https://34.132.203.172:30030/api/v1/applications/bookinfo/sync
                '''
            }
        }
    }
}
