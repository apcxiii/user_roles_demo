defmodule UserRolesDemoWeb.API.UserJSON do
  alias UserRolesDemo.Accounts.User
  alias UserRolesDemoWeb.API.RoleJSON

  @doc """
  Renders the authenticated user (`GET /api/v1/me`).
  """
  def me(%{user: user}), do: data(user)

  defp data(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      is_active: user.is_active,
      # `:roles` es un `many_to_many` (join via `users_roles`) — se preload
      # en `Accounts.fetch_user_by_token/1` antes de llegar aquí. Delegamos
      # a `RoleJSON.data/1` para no duplicar el shape de un role.
      roles: Enum.map(user.roles, &RoleJSON.data/1)
    }
  end
end
