defmodule UserRolesDemoWeb.UserLive.Index do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Accounts.subscribe_users()

    {:ok,
     socket
     |> assign(:page_title, "Usuarios")
     |> stream(:users, Accounts.list_users())}
  end

  # Estos mensajes llegan de CUALQUIER pestaña/proceso que haga
  # Accounts.create_user / update_user / delete_user
  @impl true
  def handle_info({:user_created, user}, socket) do
    {:noreply, stream_insert(socket, :users, user)}
  end

  def handle_info({:user_updated, user}, socket) do
    {:noreply, stream_insert(socket, :users, user)}
  end

  def handle_info({:user_deleted, user}, socket) do
    {:noreply, stream_delete(socket, :users, user)}
  end
end
