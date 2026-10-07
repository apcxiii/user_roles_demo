defmodule UserRolesDemoWeb.UserAuth do
  @moduledoc """
  Authentication helpers shared by the web (session-based) and API
  (Bearer token) layers.

  Web requests carry a signed `Phoenix.Token` in the session; API requests
  send that same token via the `Authorization: Bearer <token>` header. Both
  paths end up assigning `:current_user` on the `conn`.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, json: 2, put_flash: 3]

  alias UserRolesDemo.Accounts

  @user_token_session_key :user_token

  ## --- Web: token guardado en sesión ---

  @doc """
  Generates a signed token for `user` and stores it in the session.
  """
  def put_user_token(conn, user) do
    token = Accounts.generate_user_token(user)
    put_session(conn, @user_token_session_key, token)
  end

  @doc """
  Plug that loads the current user from the session token, if any, and
  assigns it as `:current_user` (`nil` when there is no token or it is
  invalid/expired).
  """
  def fetch_current_user(conn, _opts) do
    token = get_session(conn, @user_token_session_key)

    case token && Accounts.fetch_user_by_token(token) do
      {:ok, user} -> assign(conn, :current_user, user)
      _ -> assign(conn, :current_user, nil)
    end
  end

  @doc """
  Plug that halts the connection and redirects to `/login` unless
  `:current_user` is already assigned, preserving the original path in
  the session so the user can be sent back after logging in.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Debes iniciar sesión para continuar")
      |> put_session(:user_return_to, conn.request_path)
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc """
  Clears the session token and renews the session, effectively logging
  the user out.
  """
  def log_out_user(conn) do
    conn
    |> delete_session(@user_token_session_key)
    |> configure_session(renew: true)
  end

  ## --- API: mismo token, viaja como "Authorization: Bearer <token>" ---

  @doc """
  Plug that authenticates API requests via the `Authorization: Bearer
  <token>` header, assigning `:current_user` on success or halting the
  connection with a `401` JSON response otherwise.
  """
  def fetch_current_user_from_bearer(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Accounts.fetch_user_by_token(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end
end
