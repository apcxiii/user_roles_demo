defmodule UserRolesDemoWeb.RoleLive.Show do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Role")
     |> assign(:role, Accounts.get_role!(id))}
  end
end
