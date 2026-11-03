# CityResolve — image Docker pour Render.
# Contexte de build : racine du dépôt (le code applicatif est dans app/).
# Le serveur est compilé en exécutable natif : l'image finale ne contient
# ni le SDK ni le cache des paquets, seulement l'exécutable et l'interface.
# L'exécutable vit dans bin/ pour que le serveur retrouve web/ et data/
# à la racine de l'application. Il lit le port depuis la variable PORT
# fournie par Render et écoute sur 0.0.0.0.
# Sans CITYRESOLVE_MONGO_URI, il bascule en stockage JSON local
# (données de démonstration, effacées à chaque redéploiement).
FROM dart:stable AS build
WORKDIR /app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN dart pub get
COPY app/ ./
RUN dart analyze bin/server.dart
RUN dart compile exe bin/server.dart -o bin/server

FROM dart:stable
WORKDIR /app
COPY --from=build /app/bin/server ./bin/server
COPY --from=build /app/web ./web
EXPOSE 10000
CMD ["./bin/server"]
