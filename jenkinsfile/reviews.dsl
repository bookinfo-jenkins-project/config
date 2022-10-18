import java.text.SimpleDateFormat

def TODAY = (new SimpleDateFormat("yyMMddHHmm")).format(new Date())

pipeline {
    agent any

    environment {
        VERSION = "${TODAY}_${BUILD_ID}"
        PREFIX = "winterash2"
        SCRIPTDIR = "productpage"
    }
    
    stages {
        stage('Checkout') {
            steps {
                // Get some code from a GitHub repository
                git (branch: 'master'
                    , url:'https://github.com/bookinfo-jenkins-project/reviews.git')
                dir('/var/lib/jenkins/subWorkspace/bookinfo/config'){
                    git branch: 'master', url:'https://github.com/bookinfo-jenkins-project/config.git'
                }
            }
        }
        stage('Build'){
            steps{
                sh '''
                    echo \'Build Productpage\'
                    echo "Version: ${VERSION}"
                    docker run --rm -u root -v "$(pwd)":/home/gradle/project -w /home/gradle/project gradle:4.8.1 gradle clean build
                '''
                dir('./reviews-wlpcfg'){
                    script {
                        v1DockImage = docker.build("winterash2/examples-bookinfo-reviews-v1:${VERSION}", "--pull -t winterash2/examples-bookinfo-reviews-v1:${VERSION} -t winterash2/examples-bookinfo-reviews-v1:latest --build-arg service_version=v1 .")
                        v2DockImage = docker.build("winterash2/examples-bookinfo-reviews-v2:${VERSION}", "--pull -t winterash2/examples-bookinfo-reviews-v2:${VERSION} -t winterash2/examples-bookinfo-reviews-v2:latest --build-arg service_version=v2 --build-arg enable_ratings=true .")
                        v3DockImage = docker.build("winterash2/examples-bookinfo-reviews-v3:${VERSION}", "--pull -t winterash2/examples-bookinfo-reviews-v3:${VERSION} -t winterash2/examples-bookinfo-reviews-v3:latest --build-arg service_version=v3 --build-arg enable_ratings=true --build-arg star_color=red .")
                    }
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
                    docker.withRegistry('', 'DockerHub_winterash2') {
                        v3DockImage.push()
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
                    sed -i "s/examples-bookinfo-reviews-v1:.*/examples-bookinfo-reviews-v1:${VERSION}/g" bookinfo/bookinfo-reviews.yaml
                    sed -i "s/examples-bookinfo-reviews-v2:.*/examples-bookinfo-reviews-v2:${VERSION}/g" bookinfo/bookinfo-reviews.yaml
                    sed -i "s/examples-bookinfo-reviews-v3:.*/examples-bookinfo-reviews-v3:${VERSION}/g" bookinfo/bookinfo-reviews.yaml
                    git add bookinfo/bookinfo-reviews.yaml
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
