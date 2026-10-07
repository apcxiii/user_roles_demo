defmodule UserRolesDemo.Repo.Migrations.AddIsActiveToUsers do
  use Ecto.Migration

  # `default: true` deja activos a los usuarios ya existentes.
  def up do
    alter table(:users) do
      add :is_active, :boolean, default: true, null: false
    end

    create index(:users, [:is_active])
  end

  def down do
    drop index(:users, [:is_active])

    alter table(:users) do
      remove :is_active
    end
  end
end
