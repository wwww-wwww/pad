# In this file, we load production configuration and secrets
# from environment variables. You can also hardcode secrets,
# although such is generally not recommended and you have to
# remember to add this file to your .gitignore.
use Mix.Config

config :pad, Pad.Repo,
  username: "w",
  password: "1234",
  database: "etherpad",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :pad, PadWeb.Endpoint,
  http: [
    port: String.to_integer(System.get_env("PORT") || "4006")
  ],
  secret_key_base: ""

config :pad,
  api_key: ""

config :nostrum,
  token: ""
