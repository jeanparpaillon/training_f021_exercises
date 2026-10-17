FROM maven:3.9.6-eclipse-temurin-17 AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN git clone https://github.com/spring-guides/gs-rest-service.git /src
  
WORKDIR /src/complete
RUN ./mvnw package
RUN mkdir /opt/app

FROM eclipse-temurin:17-jdk-focal

EXPOSE 8080

COPY --from=build /src/complete/target/*.jar /opt/app/app.jar

CMD ["java", "-jar", "/opt/app/app.jar"]
