FROM eclipse-temurin:17-jre
WORKDIR /app
# Find the jar file in the target directory
COPY target/app.jar app.jar

# Entrypoint should be name of the jar file (set it to app.jar above)
ENTRYPOINT ["java", "-jar", "app.jar"]