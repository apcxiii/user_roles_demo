defmodule UserRolesDemo.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `UserRolesDemo.Accounts` context.
  """

  @doc """
  Generate a role.
  """
  def role_fixture(attrs \\ %{}) do
    {:ok, role} =
      attrs
      |> Enum.into(%{
        active: true,
        description: "some description",
        name: "some name"
      })
      |> UserRolesDemo.Accounts.create_role()

    role
  end

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        name: "some name",
        email: "user#{System.unique_integer()}@example.com"
      })
      |> UserRolesDemo.Accounts.create_user()

    user
  end
end
