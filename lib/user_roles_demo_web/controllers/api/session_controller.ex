defmodule UserRolesDemoWeb.API.SessionController do
  use UserRolesDemoWeb, :controller

  alias UserRolesDemo.Accounts

  # POST /api/login  {"email": "...", "password": "..."} -> {"token": "..."}
  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        json(conn, %{token: Accounts.generate_user_token(user)})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid credentials"})
    end
  end
end
