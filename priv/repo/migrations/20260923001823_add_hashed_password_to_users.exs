defmodule UserRolesDemo.Repo.Migrations.AddHashedPasswordToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :hashed_password, :string, null: false, default: ""
    end
  end

  def down do
    alter table(:users) do
      remove :hashed_password
    end
  end
end
