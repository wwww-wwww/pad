import Config

config :pad,
  ecto_repos: [Pad.Repo],
  api_url: "https://okea.moe/etherpad/api/1.2.1/",
  diff_channel: 907544630525059112,
  embed_color: 29406

# Configures the endpoint
config :pad, PadWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: PadWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Pad.PubSub,
  live_view: [signing_salt: "/KIwGxFQ"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :nostrum,
  num_shards: :auto

config :esbuild,
  version: "0.17.19",
  app: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :dart_sass,
  version: "1.63.2",
  app: [
    args: ~w(css/app.scss ../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
