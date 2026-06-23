FROM google/cloud-sdk:slim

WORKDIR /setup
COPY setup.sh .
RUN chmod +x setup.sh

ENTRYPOINT ["/bin/bash", "/setup/setup.sh"]
