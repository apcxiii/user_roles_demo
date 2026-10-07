defmodule UserRolesDemo.Repo do
  use Ecto.Repo,
    otp_app: :user_roles_demo,
    adapter: Ecto.Adapters.Postgres
end
