defmodule UserRolesDemoWeb.UserResetPasswordController do
  use UserRolesDemoWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias UserRolesDemo.Accounts

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"email" => email}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset-password/#{&1}")
      )
    end

    conn
    |> put_flash(
      :info,
      "Si tu email existe en el sistema, en breve recibirás instrucciones para restablecer la contraseña."
    )
    |> redirect(to: ~p"/login")
  end

  def edit(conn, %{"token" => token}) do
    case Accounts.fetch_user_by_reset_password_token(token) do
      {:ok, user} ->
        render(conn, :edit,
          token: token,
          form: to_form(Accounts.change_user_password(user))
        )

      {:error, _reason} ->
        conn
        |> put_flash(:error, "El link para restablecer la contraseña es inválido o ya expiró.")
        |> redirect(to: ~p"/users/reset-password")
    end
  end

  def update(conn, %{"token" => token, "user" => user_params}) do
    case Accounts.fetch_user_by_reset_password_token(token) do
      {:ok, user} ->
        case Accounts.reset_user_password(user, user_params) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "Contraseña actualizada correctamente.")
            |> redirect(to: ~p"/login")

          {:error, changeset} ->
            render(conn, :edit, token: token, form: to_form(changeset))
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "El link para restablecer la contraseña es inválido o ya expiró.")
        |> redirect(to: ~p"/users/reset-password")
    end
  end
end
