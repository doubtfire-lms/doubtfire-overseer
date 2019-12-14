FROM ubuntu:18.04

ENV PATH /home/overseer/.rbenv/bin:/home/overseer/.rbenv/shims:$PATH

# Ruby and docker-ce-cli apt dependencies
# as well as creating user 'overseer' with uid 1001
# and group 'docker' with gid 999. These accounts should
# exist on the host machine too with the same uid and gid,
# with the correct privileges.
RUN apt-get update \
    && apt-get install -qqy \
    apt-transport-https \
    ca-certificates \
    curl \
    git \
    gnupg-agent \
    software-properties-common \
    autoconf bison build-essential libssl1.0-dev libyaml-dev \
    libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm5 libgdbm-dev \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt-get update \
    && apt-get install docker-ce-cli \
    && groupadd --gid 999 docker && \
    useradd --uid 1001 --gid 999 --create-home --shell /bin/bash overseer && \
    newgrp docker

# TODO: Verify if this is required.
RUN touch /var/run/docker.sock && \
    chown 1001:999 /var/run/docker.sock \
    && mkdir /work-dir \
    && chown 1001:999 /work-dir

USER 1001:999
WORKDIR /home/overseer

RUN curl -fsSL https://github.com/rbenv/rbenv-installer/raw/master/bin/rbenv-installer | bash \
    && rbenv install 2.5.3 && rbenv global 2.5.3 \
    && gem install bundler -v 2.0.2

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

# Is not needed as long as the equivalent HOST DIR
# has been initiated with the correct FACLs.
# RUN mkdir /home/overseer/work-dir
    # && chown -R 1001:999 /home/overseer/work-dir \
    # && chmod -R 777 /home/overseer/work-dir

VOLUME [ "/home/overseer/work-dir" ]
