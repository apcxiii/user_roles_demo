defmodule UserRolesDemoWeb.PageController do
  use UserRolesDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
