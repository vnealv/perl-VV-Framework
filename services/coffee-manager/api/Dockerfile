FROM perl:5.26

COPY . /opt/app
WORKDIR /opt/app
RUN if [ -r aptfile ]; then \
            echo "installing apt deps" \
         && apt-get -y -q update \
         && apt-get -y -q --no-install-recommends install $(cat aptfile); \
            else echo "No aptfile found"; \
            fi \
         && cpanm -n --installdeps . \
         && rm -rf ~/.cpanm \
         && apt-get purge -y -q $(perl -le'@seen{split " ", "" . do { local ($/, @ARGV) = (undef, "aptfile"); <> }} = () if -r "aptfile"; print for grep { !exists $seen{$_} } qw(build-essential make gcc git openssh-client wget libssl-dev libz-dev)')


ENTRYPOINT ["perl /opt/app/bin/start.pl"]
