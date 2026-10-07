defmodule UserRolesDemo.AccountsTest do
  use UserRolesDemo.DataCase

  alias UserRolesDemo.Accounts

  describe "roles" do
    alias UserRolesDemo.Accounts.Role

    import UserRolesDemo.AccountsFixtures

    @invalid_attrs %{active: nil, name: nil, description: nil}

    test "list_roles/0 returns all roles" do
      role = role_fixture()
      assert Accounts.list_roles() == [role]
    end

    test "get_role!/1 returns the role with given id" do
      role = role_fixture()
      assert Accounts.get_role!(role.id) == role
    end

    test "create_role/1 with valid data creates a role" do
      valid_attrs = %{active: true, name: "some name", description: "some description"}

      assert {:ok, %Role{} = role} = Accounts.create_role(valid_attrs)
      assert role.active == true
      assert role.name == "some name"
      assert role.description == "some description"
    end

    test "create_role/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_role(@invalid_attrs)
    end

    test "update_role/2 with valid data updates the role" do
      role = role_fixture()

      update_attrs = %{
        active: false,
        name: "some updated name",
        description: "some updated description"
      }

      assert {:ok, %Role{} = role} = Accounts.update_role(role, update_attrs)
      assert role.active == false
      assert role.name == "some updated name"
      assert role.description == "some updated description"
    end

    test "update_role/2 with invalid data returns error changeset" do
      role = role_fixture()
      assert {:error, %Ecto.Changeset{}} = Accounts.update_role(role, @invalid_attrs)
      assert role == Accounts.get_role!(role.id)
    end

    test "delete_role/1 deletes the role" do
      role = role_fixture()
      assert {:ok, %Role{}} = Accounts.delete_role(role)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_role!(role.id) end
    end

    test "change_role/1 returns a role changeset" do
      role = role_fixture()
      assert %Ecto.Changeset{} = Accounts.change_role(role)
    end
  end

  describe "users is_active" do
    import UserRolesDemo.AccountsFixtures

    @password "supersecreta123"

    test "los usuarios nuevos quedan activos por defecto" do
      assert user_fixture().is_active
    end

    test "authenticate_user/2 rechaza a un usuario inactivo" do
      user = user_fixture(%{password: @password})
      assert {:ok, _} = Accounts.authenticate_user(user.email, @password)

      {:ok, _} = Accounts.update_user(user, %{is_active: false})
      assert {:error, :unauthorized} = Accounts.authenticate_user(user.email, @password)
    end

    test "fetch_user_by_token/1 invalida el token al desactivar al usuario" do
      user = user_fixture()
      token = Accounts.generate_user_token(user)
      assert {:ok, _} = Accounts.fetch_user_by_token(token)

      {:ok, _} = Accounts.update_user(user, %{is_active: false})
      assert {:error, :invalid_token} = Accounts.fetch_user_by_token(token)
    end
  end
end
