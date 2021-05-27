FROM perl:5.26

COPY . /opt/app
WORKDIR /opt/app

RUN echo "installing apt and cpan deps" \
      && apt-get -y -q update \
      && DEBIAN_FRONTEND=noninteractive \
      && apt-get -y -q --no-install-recommends install $(cat aptfile) \
      && cpanm -n --installdeps . \
      && rm -rf ~/.cpanm 

RUN echo "installing Framework" \
 && dzil install \
 && dzil clean \
 && git clean -fd \
 && apt purge --autoremove -y

 ENTRYPOINT ["vv-start.pl"]
