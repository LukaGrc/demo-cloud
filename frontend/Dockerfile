FROM nginx:alpine

# Remplace la config nginx par défaut (Cloud Run écoute sur 8080)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copie le site statique
COPY index.html /usr/share/nginx/html/index.html
