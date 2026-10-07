defmodule UserRolesDemoWeb.GraphQL.Resolvers.Accounts do
  @moduledoc """
  Resolvers for the `Accounts` context, used by `UserRolesDemoWeb.GraphQL.Schema`.
  """

  alias UserRolesDemo.Accounts

  def me(_parent, _args, %{context: %{current_user: user}}), do: {:ok, user}
  def me(_parent, _args, _resolution), do: {:error, "unauthenticated"}

  def roles(_parent, _args, _resolution), do: {:ok, Accounts.list_roles()}

  def login(_parent, %{email: email, password: password}, _resolution) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} -> {:ok, %{token: Accounts.generate_user_token(user), user: user}}
      {:error, :unauthorized} -> {:error, "invalid credentials"}
    end
  end
end
