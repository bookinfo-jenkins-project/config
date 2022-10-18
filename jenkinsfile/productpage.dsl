import java.text.SimpleDateFormat

def TODAY = (new SimpleDateFormat("yyMMddHHmm")).format(new Date())

pipeline {
  agent any

  environment {
    VERSION = "${TODAY}_${BUILD_ID}"
    PREFIX = "winterash2"
    SCRIPTDIR = "productpage"
    DOCKERIMAGE = "winterash2/examples-bookinfo-productpage-v1:${VERSION}"
  }
  
  stages {
    stage('Checkout') {
      steps {
        // Get some code from a GitHub repository
        git (branch: 'master'
          , url:'https://github.com/bookinfo-jenkins-project/productpage.git')
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
        '''
        script {
          oDockImage = docker.build("winterash2/examples-bookinfo-productpage-v1:${VERSION}", "--pull -t winterash2/examples-bookinfo-productpage-v1:${VERSION} -t winterash2/examples-bookinfo-productpage-v1:latest -f Dockerfile .")
          fDockImage = docker.build("winterash2/examples-bookinfo-productpage-v-flooding:${VERSION}", "--pull -t winterash2/examples-bookinfo-productpage-v-flooding:${VERSION} -t winterash2/examples-bookinfo-productpage-v-flooding:latest -f Dockerfile .")
        }
      }
    }
    stage('Docker Image Push') {
      steps {
        script {
          docker.withRegistry('', 'DockerHub_winterash2') {
            oDockImage.push()
          }
          docker.withRegistry('', 'DockerHub_winterash2') {
            fDockImage.push()
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
            sed -i "s/examples-bookinfo-productpage-v1:.*/examples-bookinfo-productpage-v1:${VERSION}/g" bookinfo/bookinfo-productpage.yaml
            git add bookinfo/bookinfo-productpage.yaml
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
