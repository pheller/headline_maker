# syntax=docker/dockerfile:1
# Build stage for the content-batch image: a self-contained mix release of the
# headline generator.
#
# This image is not meant to run on its own - content-batch assembles it:
#   COPY --from=<this> /app/_build/prod/rel/headline_maker ...
#
# Unlike weather_overlay there are no native dependencies, so the release is
# the whole story. It does need network at build time: naplps_writer and
# prodigy_objects are git deps.

FROM elixir:1.17.3-otp-27 AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
COPY lib lib
RUN mix deps.compile && mix compile && mix release --overwrite
