defmodule UserRolesDemo.Repo.Migrations.CreateUsersRoles do
  use Ecto.Migration

  def up do
    create table(:users_roles, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role_id, references(:roles, on_delete: :delete_all), null: false
    end

    create unique_index(:users_roles, [:user_id, :role_id])
  end

  def down do
    drop table(:users_roles)
  end
end
