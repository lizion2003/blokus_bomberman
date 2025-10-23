FROM hexpm/elixir:1.17.2-erlang-27.0-alpine-3.20.1 AS build

# Install build dependencies
RUN apk add --no-cache build-base git

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before compiling dependencies
COPY config/config.exs config/${MIX_ENV}.exs config/runtime.exs config/
RUN mix deps.compile

# Copy priv and assets
COPY priv priv
COPY assets assets

# Compile and build release
COPY lib lib
RUN mix compile

# Build assets (Phoenix 1.7+ uses esbuild)
RUN mix assets.deploy

# Build release
RUN mix release

# Prepare release image
FROM alpine:3.20.1 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/blokus_bomberman ./

ENV HOME=/app
ENV MIX_ENV=prod
ENV PORT=4000
ENV PHX_SERVER=true

CMD ["bin/blokus_bomberman", "start"]
