defmodule Pad.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Pad.Repo,
      {DynamicSupervisor, name: Pad.DynamicSupervisor, strategy: :one_for_one},
      Pad.ProcessRegistry,
      Pad.Songlist,
      # Start the Telemetry supervisor
      PadWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Pad.PubSub},
      # Start the Endpoint (http/https)
      PadWeb.Endpoint,
      Pad.Paginator,
      Pad.Consumer
    ]

    opts = [strategy: :one_for_one, name: Pad.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    PadWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def regen_pass() do
    password = Bcrypt.gen_salt()
    Application.put_env(:pad, :superdelete, Bcrypt.hash_pwd_salt(password))
    password
  end

  def check_password(password) do
    case Application.get_env(:pad, :superdelete) do
      nil -> false
      key -> Bcrypt.verify_pass(password, key)
    end
  end
end
