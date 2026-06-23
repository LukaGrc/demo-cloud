#!/bin/sh
# Injecte API_URL dans le HTML au démarrage du conteneur, puis lance nginx.
envsubst '${API_URL}' < /usr/share/nginx/html/index.html.tmpl \
  > /usr/share/nginx/html/index.html
exec nginx -g "daemon off;"
