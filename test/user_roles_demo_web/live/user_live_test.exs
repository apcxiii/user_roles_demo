defmodule UserRolesDemoWeb.UserLiveTest do
  use UserRolesDemoWeb.ConnCase

  import Phoenix.LiveViewTest
  import UserRolesDemo.AccountsFixtures

  setup :register_and_log_in_user

  @create_attrs %{name: "some name", email: "some@example.com", password: "supersecreta123"}
  @update_attrs %{name: "some updated name", email: "updated@example.com"}
  @invalid_attrs %{name: nil, email: nil}

  defp create_user(_) do
    user = user_fixture()

    %{user: user}
  end

  describe "Index" do
    setup [:create_user]

    test "lists all users", %{conn: conn, user: user} do
      {:ok, _index_live, html} = live(conn, ~p"/users")

      assert html =~ "Usuarios"
      assert html =~ user.name
    end

    test "saves new user", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/users")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "Nuevo usuario")
               |> render_click()
               |> follow_redirect(conn, ~p"/users/new")

      assert render(form_live) =~ "New User"

      assert form_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#user-form", user: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/users")

      html = render(index_live)
      assert html =~ "User created successfully"
      assert html =~ "some name"
    end

    test "updates user in listing", %{conn: conn, user: user} do
      {:ok, index_live, _html} = live(conn, ~p"/users")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#users-#{user.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/users/#{user}/edit")

      assert render(form_live) =~ "Edit User"

      assert form_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#user-form", user: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/users")

      html = render(index_live)
      assert html =~ "User updated successfully"
      assert html =~ "some updated name"
    end

    test "assigns selected roles when creating a user", %{conn: conn} do
      role = role_fixture()

      {:ok, form_live, _html} = live(conn, ~p"/users/new")

      assert {:ok, index_live, _html} =
               form_live
               |> form("#user-form", user: @create_attrs, role_ids: [role.id])
               |> render_submit()
               |> follow_redirect(conn, ~p"/users")

      html = render(index_live)
      assert html =~ role.name
    end
  end
end
