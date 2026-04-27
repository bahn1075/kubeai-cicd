FROM substratusai/kubeai-model-loader:main

COPY LGCNS_CA_v3.crt /usr/local/share/ca-certificates/LGCNS_CA_v3.crt

RUN cat /usr/local/share/ca-certificates/LGCNS_CA_v3.crt >> /etc/ssl/certs/ca-certificates.crt

ENV HF_HUB_DISABLE_XET=1
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
