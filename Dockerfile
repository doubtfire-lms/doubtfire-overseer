FROM ruby:2.5.3

RUN groupadd --gid 1101 watch && \
    useradd --uid 1001 --gid 1101 --create-home --shell /bin/bash overseer
USER 1001:1101
WORKDIR /home/overseer/app

RUN gem install bundler -v 2.0.2

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /home/overseer/app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
