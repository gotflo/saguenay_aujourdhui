# À construire depuis la racine du dépôt (le serveur utilise le cœur) :
#   docker build -f server/Dockerfile -t saguenay-assistant .
#   docker run -p 8080:8080 -e ANTHROPIC_API_KEY=... saguenay-assistant
FROM dart:stable AS build
RUN apt-get update && apt-get install -y --no-install-recommends tzdata && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY packages/saguenay_core packages/saguenay_core
COPY server server
WORKDIR /src/server
RUN dart pub get && dart compile exe bin/server.dart -o /src/assistant

FROM scratch
COPY --from=build /runtime/ /
# Les heures dites par texto ou au téléphone sont celles de Saguenay.
COPY --from=build /usr/share/zoneinfo/America/Toronto /usr/share/zoneinfo/America/Toronto
ENV TZ=America/Toronto
COPY --from=build /src/assistant /app/assistant
EXPOSE 8080
CMD ["/app/assistant"]
