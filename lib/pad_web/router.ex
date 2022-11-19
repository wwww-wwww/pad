defmodule PadWeb.Router do
  use PadWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PadWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/create", PageController, :create
    post "/create", PageController, :create

    get "/delete", PageController, :delete
    post "/delete", PageController, :delete

    get "/superdelete", PageController, :superdelete
    post "/superdelete", PageController, :superdelete
  end

  scope "/", PadWeb do
    pipe_through :api

    get "/diff/:file", ApiController, :diff
    get "/songinfo/:file", ApiController, :songinfo
  end

  scope "/api", PadWeb do
    pipe_through :api

    get "/pads", ApiController, :list_pads
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: PadWeb.Telemetry
    end
  end

  scope "/", PadWeb do
    pipe_through :browser

    # Catch all at the end
    get "/:id", PageController, :index
  end
end
