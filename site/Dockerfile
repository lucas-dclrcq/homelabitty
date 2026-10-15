# syntax=docker/dockerfile:1

# --- build stage: build the Quarkus app (Roq renders the site at runtime) ---
FROM maven:3.10-eclipse-temurin-21 AS build
WORKDIR /src

COPY . .

RUN ./site/sync-content.sh \
    && cd site \
    && mvn -B -q -e package

# --- runtime stage: run the Quarkus app ---
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app
COPY --from=build /src/site/target/quarkus-app/ /app/

USER 101
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/quarkus-run.jar"]
