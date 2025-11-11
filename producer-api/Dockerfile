FROM eclipse-temurin:17-jdk

WORKDIR /app

COPY build/libs/*.jar app.jar

EXPOSE 8081

# JAVA_OPTS will be passed from docker-compose environment
ENTRYPOINT sh -c 'java $JAVA_OPTS -jar app.jar'
