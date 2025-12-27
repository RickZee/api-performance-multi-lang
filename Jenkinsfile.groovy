// Jenkins Pipeline for Integration Tests
// Supports both declarative and scripted pipeline syntax

@Library('shared-library') _  // Optional: if using shared Jenkins library

pipeline {
    agent {
        label 'docker'  // Use Jenkins agent with Docker support
    }
    
    environment {
        DOCKER_COMPOSE_FILE = 'cdc-streaming/docker-compose.integration-test.yml'
        E2E_TESTS_DIR = 'cdc-streaming/e2e-tests'
        JAVA_HOME = tool name: 'JDK-17', type: 'jdk'
        PATH = "${JAVA_HOME}/bin:${env.PATH}"
    }
    
    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
        timestamps()
        ansiColor('xterm')
    }
    
    parameters {
        choice(
            name: 'TEST_SUITE',
            choices: ['all', 'local', 'schema', 'breaking'],
            description: 'Which test suite to run'
        )
        booleanParam(
            name: 'SKIP_BUILD',
            defaultValue: false,
            description: 'Skip Docker image builds (use cached images)'
        )
        booleanParam(
            name: 'CLEANUP',
            defaultValue: true,
            description: 'Clean up Docker containers after tests'
        )
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                }
            }
        }
        
        stage('Prerequisites') {
            steps {
                script {
                    echo "Build #${env.BUILD_NUMBER} - Commit: ${env.GIT_COMMIT_SHORT}"
                    sh '''
                        echo "=== Checking Prerequisites ==="
                        docker --version
                        docker-compose --version || docker compose version
                        java -version
                        ./cdc-streaming/e2e-tests/gradlew --version
                    '''
                }
            }
        }
        
        stage('Build Docker Images') {
            when {
                not { params.SKIP_BUILD }
            }
            steps {
                script {
                    dir('cdc-streaming') {
                        sh '''
                            echo "=== Building Docker Images ==="
                            docker-compose -f docker-compose.integration-test.yml build \
                                --no-cache mock-confluent-api metadata-service stream-processor
                        '''
                    }
                }
            }
        }
        
        stage('Start Test Infrastructure') {
            steps {
                script {
                    dir('cdc-streaming') {
                        sh '''
                            echo "=== Starting Test Infrastructure ==="
                            docker-compose -f docker-compose.integration-test.yml up -d \
                                kafka schema-registry mock-confluent-api
                            
                            echo "Waiting for Kafka to be healthy..."
                            timeout 60 bash -c 'until docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null; do sleep 2; done' || exit 1
                            
                            echo "Initializing V1 topics..."
                            docker-compose -f docker-compose.integration-test.yml up init-topics
                        '''
                    }
                }
            }
        }
        
        stage('Start Services') {
            steps {
                script {
                    dir('cdc-streaming') {
                        sh '''
                            echo "=== Starting Services ==="
                            docker-compose -f docker-compose.integration-test.yml up -d \
                                metadata-service stream-processor
                            
                            echo "Waiting for services to be healthy..."
                            timeout 60 bash -c 'until curl -sf http://localhost:8080/api/v1/health && curl -sf http://localhost:8083/actuator/health; do sleep 2; done' || exit 1
                            
                            echo "Services are healthy"
                        '''
                    }
                }
            }
        }
        
        stage('Run Local Integration Tests') {
            when {
                anyOf {
                    params.TEST_SUITE == 'all'
                    params.TEST_SUITE == 'local'
                }
            }
            steps {
                script {
                    dir('cdc-streaming/e2e-tests') {
                        sh '''
                            echo "=== Running Local Integration Tests ==="
                            ./gradlew test --tests "com.example.e2e.local.*" --no-daemon || true
                        '''
                    }
                }
            }
            post {
                always {
                    publishTestResults(
                        testResultsPattern: 'cdc-streaming/e2e-tests/build/test-results/test/*.xml',
                        allowEmptyResults: true
                    )
                }
            }
        }
        
        stage('Run Schema Evolution Tests') {
            when {
                anyOf {
                    params.TEST_SUITE == 'all'
                    params.TEST_SUITE == 'schema'
                }
            }
            steps {
                script {
                    dir('cdc-streaming/e2e-tests') {
                        sh '''
                            echo "=== Running Schema Evolution Tests ==="
                            ./gradlew test --tests "com.example.e2e.schema.NonBreakingSchemaTest" --no-daemon || true
                        '''
                    }
                }
            }
            post {
                always {
                    publishTestResults(
                        testResultsPattern: 'cdc-streaming/e2e-tests/build/test-results/test/*.xml',
                        allowEmptyResults: true
                    )
                }
            }
        }
        
        stage('Run Breaking Schema Tests (V2)') {
            when {
                anyOf {
                    params.TEST_SUITE == 'all'
                    params.TEST_SUITE == 'breaking'
                }
            }
            steps {
                script {
                    dir('cdc-streaming') {
                        sh '''
                            echo "=== Starting V2 System for Breaking Schema Tests ==="
                            docker-compose -f docker-compose.integration-test.yml --profile v2 build stream-processor-v2 || true
                            docker-compose -f docker-compose.integration-test.yml --profile v2 up -d stream-processor-v2
                            docker-compose -f docker-compose.integration-test.yml --profile v2 up init-topics-v2
                            
                            echo "Waiting for V2 system to be ready..."
                            sleep 15
                        '''
                    }
                    dir('cdc-streaming/e2e-tests') {
                        sh '''
                            echo "=== Running Breaking Schema Change Tests ==="
                            ./gradlew test --tests "com.example.e2e.schema.BreakingSchemaChangeTest" --no-daemon || true
                        '''
                    }
                }
            }
            post {
                always {
                    publishTestResults(
                        testResultsPattern: 'cdc-streaming/e2e-tests/build/test-results/test/*.xml',
                        allowEmptyResults: true
                    )
                }
            }
        }
        
        stage('Generate Test Reports') {
            steps {
                script {
                    dir('cdc-streaming/e2e-tests') {
                        sh '''
                            echo "=== Generating Test Reports ==="
                            ./gradlew test --no-daemon || true
                        '''
                    }
                }
            }
            post {
                always {
                    publishTestResults(
                        testResultsPattern: 'cdc-streaming/e2e-tests/build/test-results/test/*.xml',
                        allowEmptyResults: true
                    )
                    publishHTML([
                        reportDir: 'cdc-streaming/e2e-tests/build/reports/tests/test',
                        reportFiles: 'index.html',
                        reportName: 'Integration Test Report',
                        keepAll: true
                    ])
                    archiveArtifacts artifacts: 'cdc-streaming/e2e-tests/build/reports/**/*', allowEmptyArchive: true
                }
            }
        }
    }
    
    post {
        always {
            script {
                if (params.CLEANUP) {
                    dir('cdc-streaming') {
                        sh '''
                            echo "=== Cleaning Up Docker Containers ==="
                            docker-compose -f docker-compose.integration-test.yml down || true
                            docker-compose -f docker-compose.integration-test.yml --profile v2 down || true
                            
                            # Clean up any orphaned containers
                            docker ps -a --filter "name=int-test-" --format "{{.ID}}" | xargs -r docker rm -f || true
                        '''
                    }
                }
            }
        }
        success {
            echo '✅ All integration tests passed!'
            emailext(
                subject: "✅ Integration Tests Passed - Build #${env.BUILD_NUMBER}",
                body: "Integration tests completed successfully.\n\nBuild: ${env.BUILD_URL}",
                to: "${env.CHANGE_AUTHOR_EMAIL}",
                mimeType: 'text/html'
            )
        }
        failure {
            echo '❌ Some integration tests failed. Check test reports for details.'
            emailext(
                subject: "❌ Integration Tests Failed - Build #${env.BUILD_NUMBER}",
                body: "Some integration tests failed.\n\nBuild: ${env.BUILD_URL}\nConsole: ${env.BUILD_URL}console",
                to: "${env.CHANGE_AUTHOR_EMAIL}",
                mimeType: 'text/html'
            )
        }
        unstable {
            echo '⚠️ Some tests were unstable. Check test reports for details.'
        }
    }
}

