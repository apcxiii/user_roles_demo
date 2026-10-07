defmodule UserRolesDemoWeb.RoleLive.Index do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Roles")
     |> stream(:roles, list_roles())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    role = Accounts.get_role!(id)
    {:ok, _} = Accounts.soft_delete_role(role)

    {:noreply, stream_delete(socket, :roles, role)}
  end

  defp list_roles do
    Accounts.list_roles()
  end
end
