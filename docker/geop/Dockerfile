FROM eclipse-temurin:8-jre

ARG GEOP_VERSION=6.1.0
ENV GEOP_VERSION=${GEOP_VERSION}

WORKDIR /opt/geoprocessing

RUN curl -fsSL \
    -o /opt/geoprocessing/mmw-geoprocessing-${GEOP_VERSION}.jar \
    https://github.com/WikiWatershed/mmw-geoprocessing/releases/download/${GEOP_VERSION}/api-assembly-${GEOP_VERSION}.jar

EXPOSE 8090

CMD ["sh", "-c", "java -jar /opt/geoprocessing/mmw-geoprocessing-${GEOP_VERSION}.jar"]
