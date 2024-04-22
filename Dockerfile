FROM ruby:3.3.0-slim-bookworm

WORKDIR /app
COPY * /app/

RUN set -eux ; \
    bundle install

ENTRYPOINT ["bundle", "exec", "ruby", "server.rb"]
