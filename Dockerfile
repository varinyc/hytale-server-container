FROM eclipse-temurin:25-jdk
RUN apt-get update && apt-get install -y curl unzip bash jq tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 5520/udp

ENTRYPOINT ["/app/start.sh"]
