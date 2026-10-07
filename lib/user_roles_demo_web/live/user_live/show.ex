defmodule UserRolesDemoWeb.UserLive.Show do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Usuario")
     |> assign(:user, Accounts.get_user!(id))}
  end
end
