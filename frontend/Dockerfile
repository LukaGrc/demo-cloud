FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY entrypoint.sh /entrypoint.sh
COPY index.html /usr/share/nginx/html/index.html.tmpl

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
