FROM elixir:1.17-alpine

# Install system dependencies
RUN apk add --no-cache --update git build-base nodejs npm inotify-tools

WORKDIR /app

# Install Mix dependencies
RUN mix local.hex --force && mix local.rebar --force

# Copy the entire repository
COPY . .

# Install Elixir dependencies
RUN mix deps.get

# Set up assets (install tailwind and esbuild if missing)
RUN mix assets.setup

# Build assets initially
RUN mix assets.build

# Expose the Phoenix port
EXPOSE 4000

# Set environment to development by default
ENV MIX_ENV=dev

# Start the Phoenix server
CMD ["mix", "phx.server"]