# ---- Build Stage ----
# Using '17-jdk' instead of alpine for better Mac (ARM64) support
FROM eclipse-temurin:17-jdk AS build
WORKDIR /app

# Copy Maven wrapper and configuration
COPY .mvn/ .mvn
COPY mvnw pom.xml ./

# Fix permissions and download dependencies (cached)
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B

# Copy source code and build
COPY src ./src
RUN ./mvnw clean package -DskipTests

# ---- Runtime Stage ----
# Using '17-jre' which is guaranteed to work on Apple Silicon
FROM eclipse-temurin:17-jre
WORKDIR /app

# Copy the built JAR from the build stage
COPY --from=build /app/target/*.jar app.jar

ENTRYPOINT ["java", "-jar", "app.jar"]