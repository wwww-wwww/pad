defmodule Pad.Repo do
  use Ecto.Repo,
    otp_app: :pad,
    adapter: Ecto.Adapters.Postgres
end
