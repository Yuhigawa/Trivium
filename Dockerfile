FROM elixir:1.17-otp-27

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      ca-certificates \
      ripgrep \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=dev \
    LANG=C.UTF-8 \
    HOME=/home/yuhigawa \
    PATH=/home/yuhigawa/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock* ./
RUN mix deps.get 2>/dev/null || true

COPY . .

CMD ["iex", "-S", "mix"]
