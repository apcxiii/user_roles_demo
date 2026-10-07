defmodule UserRolesDemo.Accounts.UserNotifier do
  @moduledoc """
  Builds and delivers transactional emails for the `Accounts` context
  (currently just the reset-password instructions).
  """

  import Swoosh.Email

  alias UserRolesDemo.Mailer

  defp deliver(to, subject, body) do
    email =
      new()
      |> to(to)
      |> from({"UserRolesDemo", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """
    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this email. The link
    above expires shortly and stops working as soon as a new password is set.

    ==============================
    """)
  end
end
