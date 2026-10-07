defmodule UserRolesDemoWeb.GraphQL.Context do
  @moduledoc """
  Plug that builds the Absinthe context from the same `Authorization: Bearer
  <token>` header the REST API uses (`UserRolesDemoWeb.UserAuth`). A missing
  or invalid token simply means no `current_user` in context — queries that
  need one (ej. `me`) devuelven su propio error desde el resolver, en vez de
  cortar la conexión como hace el plug REST.
  """

  @behaviour Plug

  import Plug.Conn

  alias UserRolesDemo.Accounts

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Absinthe.Plug.put_options(conn, context: build_context(conn))
  end

  defp build_context(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Accounts.fetch_user_by_token(token) do
      %{current_user: user}
    else
      _ -> %{}
    end
  end
end
