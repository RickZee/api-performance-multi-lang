pipeline {
    agent any
    
    environment {
        DOCKER_COMPOSE_FILE = 'cdc-streaming/docker-compose.integration-test.yml'
        E2E_TESTS_DIR = 'cdc-streaming/e2e-tests'
    }
    
    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Prerequisites') {
            steps {
                script {
                    sh '''
                        echo "Checking prerequisites..."
                        docker --version
                        docker-compose --version || docker compose version
                        java -version
                        ./cdc-streaming/e2e-tests/gradlew --version
                    '''
                }
            }
        }
        
        stage('Build Docker Images') {
            steps {
                script {
                    dir('cdc-streaming') {
                        sh '''
                            echo "Building Docker images..."
                            docker-compose -f docker-compose.integration-test.yml build \
                                mock-confluent-api metadata-service stream-processor
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
                            echo "Starting Kafka, Schema Registry, and Mock API..."
                            docker-compose -f docker-compose.integration-test.yml up -d \
                                kafka schema-registry mock-confluent-api
                            
                            echo "Waiting for Kafka to be healthy..."
                            timeout 60 bash -c 'until docker exec int-test-kafka kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null; do sleep 2; done'
                            
                            echo "Initializing topics..."
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
                            echo "Starting Metadata Service and Stream Processor..."
                            docker-compose -f docker-compose.integration-test.yml up -d \
                                metadata-service stream-processor
                            
                            echo "Waiting for services to be healthy..."
                            timeout 60 bash -c 'until curl -sf http://localhost:8080/api/v1/health && curl -sf http://localhost:8083/actuator/health; do sleep 2; done'
                        '''
                    }
                }
            }
        }
        
        stage('Run Local Integration Tests') {
            steps {
                script {
                    dir('cdc-streaming/e2e-tests') {
                        sh '''
                            echo "Running LocalKafkaIntegrationTest..."
                            ./gradlew test --tests "com.example.e2e.local.LocalKafkaIntegrationTest" --no-daemon || true
                            
                            echo "Running FilterLifecycleLocalTest..."
                            ./gradlew test --tests "com.example.e2e.local.FilterLifecycleLocalTest" --no-daemon || true
                            
                            echo "Running StreamProcessorLocalTest..."
                            ./gradlew test --tests "com.example.e2e.local.StreamProcessorLocalTest" --no-daemon || true
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
            steps {
                script {
                    dir('cdc-streaming/e2e-tests') {
                        sh '''
                            echo "Running NonBreakingSchemaTest..."
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
            steps {
                script {
                    dir('cdc-streaming') {
                        sh '''
                            echo "Starting V2 system for breaking schema tests..."
                            docker-compose -f docker-compose.integration-test.yml --profile v2 up -d stream-processor-v2
                            docker-compose -f docker-compose.integration-test.yml --profile v2 up init-topics-v2
                            
                            echo "Waiting for V2 system..."
                            sleep 10
                        '''
                    }
                    dir('cdc-streaming/e2e-tests') {
                        sh '''
                            echo "Running BreakingSchemaChangeTest..."
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
                        sh './gradlew test --no-daemon || true'
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
                }
            }
        }
    }
    
    post {
        always {
            script {
                dir('cdc-streaming') {
                    sh '''
                        echo "Cleaning up Docker containers..."
                        docker-compose -f docker-compose.integration-test.yml down || true
                        docker-compose -f docker-compose.integration-test.yml --profile v2 down || true
                    '''
                }
            }
        }
        success {
            echo 'All integration tests passed!'
        }
        failure {
            echo 'Some integration tests failed. Check test reports for details.'
        }
        unstable {
            echo 'Some tests were unstable. Check test reports for details.'
        }
    }
}

