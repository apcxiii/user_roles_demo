defmodule UserRolesDemoWeb.Router do
  use UserRolesDemoWeb, :router

  import UserRolesDemoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UserRolesDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug :fetch_current_user_from_bearer
  end

  pipeline :graphql_context do
    plug UserRolesDemoWeb.GraphQL.Context
  end

  # GraphiQL (solo dev) necesita poder servir HTML además de JSON —
  # con el pipeline :api (solo "json") tira Phoenix.NotAcceptableError.
  pipeline :graphiql do
    plug :accepts, ["html", "json"]
  end

  scope "/", UserRolesDemoWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    get "/users/reset-password", UserResetPasswordController, :new
    post "/users/reset-password", UserResetPasswordController, :create
    get "/users/reset-password/:token", UserResetPasswordController, :edit
    put "/users/reset-password/:token", UserResetPasswordController, :update
  end

  scope "/", UserRolesDemoWeb do
    pipe_through [:browser, :authenticated]

    live "/roles", RoleLive.Index, :index
    live "/roles/new", RoleLive.Form, :new
    live "/roles/:id", RoleLive.Show, :show
    live "/roles/:id/edit", RoleLive.Form, :edit

    live "/users", UserLive.Index, :index
    live "/users/new", UserLive.Form, :new
    live "/users/:id", UserLive.Show, :show
    live "/users/:id/edit", UserLive.Form, :edit
  end

  # API versionada: /api/v1/... — login público (emite token) + rutas
  # protegidas con Bearer. El prefijo /v1 deja lugar para un /api/v2 el día
  # que haya que romper compatibilidad sin tocar a los clientes existentes.
  scope "/api/v1", UserRolesDemoWeb.API do
    pipe_through :api

    post "/login", SessionController, :create
  end

  scope "/api/v1", UserRolesDemoWeb.API do
    pipe_through [:api, :api_auth]

    get "/me", UserController, :me
  end

  # GraphQL: no versionamos la URL (/api/graphql, no /api/v1/graphql) — el
  # schema evoluciona agregando campos o marcándolos @deprecated, no con un
  # prefijo nuevo por cada cambio (ver sección 8.3).
  scope "/api" do
    pipe_through [:api, :graphql_context]

    forward "/graphql", Absinthe.Plug, schema: UserRolesDemoWeb.GraphQL.Schema
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:user_roles_demo, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: UserRolesDemoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/api" do
      pipe_through [:graphiql, :graphql_context]

      forward "/graphiql", Absinthe.Plug.GraphiQL,
        schema: UserRolesDemoWeb.GraphQL.Schema,
        interface: :simple
    end
  end
end
