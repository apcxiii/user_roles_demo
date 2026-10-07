defmodule UserRolesDemoWeb.API.UserController do
  use UserRolesDemoWeb, :controller

  # GET /api/v1/me  (requiere "Authorization: Bearer <token>")
  def me(conn, _params) do
    render(conn, :me, user: conn.assigns.current_user)
  end
end
