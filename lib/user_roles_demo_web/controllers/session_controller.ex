defmodule UserRolesDemoWeb.SessionController do
  use UserRolesDemoWeb, :controller

  alias UserRolesDemo.Accounts
  alias UserRolesDemoWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> UserAuth.put_user_token(user)
        |> redirect(to: ~p"/users")

      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "Email o contraseña inválidos")
        |> render(:new)
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/login")
  end
end
