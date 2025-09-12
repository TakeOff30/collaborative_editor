# Dockerfile for Phoenix Application (Development)

FROM elixir:1.15-slim

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# install dependencies
COPY mix.exs mix.lock ./

RUN mix deps.get && mix deps.compile

COPY . .

ENV MIX_ENV=dev
ENV PORT=4000
ENV PHX_SERVER=true

EXPOSE 4000

# `mix phx.server` is used for development to enable code reloading.
CMD ["mix", "phx.server"]
