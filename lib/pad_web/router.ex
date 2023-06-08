defmodule PadWeb.Router do
  use PadWeb, :router

  import PadWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PadWeb do
    pipe_through :browser

    get "/", PageController, :index

    get "/u/:username", UserController, :user

    get "/sign_out", UserController, :sign_out

    scope "/" do
      pipe_through :redirect_if_user_is_authenticated

      get "/sign_in", UserController, :sign_in
      post "/sign_in", UserController, :sign_in

      get "/sign_up", UserController, :sign_up
      post "/sign_up", UserController, :sign_up
    end

    scope "/" do
      pipe_through :require_authenticated_user

      post "/change_password", UserController, :change_password

      post "/claim_pad", UserController, :claim_pad
      post "/delete_pad", UserController, :delete_pad

      get "/create_pad", UserController, :create_pad
      post "/create_pad", UserController, :create_pad
    end
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
