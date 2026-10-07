defmodule UserRolesDemoWeb.API.RoleJSON do
  alias UserRolesDemo.Accounts.Role

  @doc """
  Renders a single role. Reutilizado por `UserJSON` para serializar la
  asociación `many_to_many :roles` de `User` (y por cualquier otro endpoint
  que devuelva roles, ej. un futuro `GET /api/v1/roles`).
  """
  def data(%Role{} = role) do
    %{
      id: role.id,
      name: role.name,
      description: role.description,
      active: role.active
    }
  end
end
