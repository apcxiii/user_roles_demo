defmodule UserRolesDemoWeb.UserLive.Form do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts
  alias UserRolesDemo.Accounts.User

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:roles, Accounts.list_roles())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = Accounts.get_user!(id)

    socket
    |> assign(:page_title, "Edit User")
    |> assign(:user, user)
    |> assign(:selected_role_ids, Enum.map(user.roles, & &1.id))
    |> assign(:form, to_form(Accounts.change_user(user)))
  end

  defp apply_action(socket, :new, _params) do
    user = %User{}

    socket
    |> assign(:page_title, "New User")
    |> assign(:user, user)
    |> assign(:selected_role_ids, [])
    |> assign(:form, to_form(Accounts.change_user_registration(user)))
  end

  @impl true
  def handle_event("validate", %{"user" => user_params} = params, socket) do
    changeset = build_changeset(socket, user_params)

    {:noreply,
     socket
     |> assign(:selected_role_ids, role_ids(params))
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => user_params} = params, socket) do
    save_user(socket, socket.assigns.live_action, user_params, role_ids(params))
  end

  defp build_changeset(socket, user_params) do
    case socket.assigns.live_action do
      :new -> Accounts.change_user_registration(socket.assigns.user, user_params)
      :edit -> Accounts.change_user(socket.assigns.user, user_params)
    end
  end

  defp role_ids(params) do
    params
    |> Map.get("role_ids", [])
    |> Enum.map(&String.to_integer/1)
  end

  defp save_user(socket, :edit, user_params, role_ids) do
    case Accounts.update_user(socket.assigns.user, user_params, role_ids) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated successfully")
         |> push_navigate(to: ~p"/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_user(socket, :new, user_params, role_ids) do
    case Accounts.register_user(user_params, role_ids) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User created successfully")
         |> push_navigate(to: ~p"/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
