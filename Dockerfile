# CityResolve — image Docker pour Render.
# Contexte de build : racine du dépôt (le code applicatif est dans app/).
# Le serveur lit le port depuis la variable PORT fournie par Render,
# écoute sur 0.0.0.0, et sert l'interface sur / et /api/health.
# Sans CITYRESOLVE_MONGO_URI, il bascule en stockage JSON local
# (données de démonstration, effacées à chaque redéploiement).
FROM dart:stable AS build
WORKDIR /app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN dart pub get
COPY app/ ./
RUN dart analyze bin/server.dart

FROM dart:stable
WORKDIR /app
COPY --from=build /app /app
EXPOSE 10000
CMD ["dart", "bin/server.dart"]
