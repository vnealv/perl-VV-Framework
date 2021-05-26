FROM perl-vv-framework

COPY . /app
WORKDIR /app
RUN if [ -r aptfile ]; then \
   echo "installing apt deps" \
   && apt-get -y -q update \
   && DEBIAN_FRONTEND=noninteractive \
   && apt-get -y -q --no-install-recommends install $(cat aptfile); \
  else echo "No aptfile found"; \
 fi 

RUN if [ -r cpanfile ]; then \
   cpanm -n --installdeps . \
   && rm -rf ~/.cpanm; \
 fi

