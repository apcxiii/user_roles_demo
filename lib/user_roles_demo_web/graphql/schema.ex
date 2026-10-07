defmodule UserRolesDemoWeb.GraphQL.Schema do
  @moduledoc """
  GraphQL schema for the public API, mounted at `/api/graphql` (and
  `/api/graphiql` in dev). Complements the REST API (`/api/v1`, sección 8)
  sin reemplazarla.

  Un solo endpoint HTTP (`POST /api/graphql`) sirve los dos tipos de
  operación de abajo — `query` (lectura) y `mutation` (escritura) — el
  `query` dentro del body de la request es lo que decide cuál corre.

  ## Query (lectura, ej. `roles`)

      curl -s -X POST http://localhost:4000/api/graphql \\
        -H "Content-Type: application/json" \\
        -d '{"query":"{ roles { id name active } }"}'
      # => {"data":{"roles":[{"active":true,"id":"1","name":"admin"}, ...]}}

  ## Mutation (escritura, ej. `login`)

      curl -s -X POST http://localhost:4000/api/graphql \\
        -H "Content-Type: application/json" \\
        -d '{"query":"mutation { login(email: \\"admin@example.com\\", password: \\"supersecreta123\\") { token user { id name } } }"}'
      # => {"data":{"login":{"token":"SFMyNTY....","user":{"id":"1","name":"Admin"}}}}

  `me` (query protegida) necesita además el token de arriba en
  `Authorization: Bearer <token>` — ver sección 8.3.5 de la guía para el
  ejemplo completo.
  """

  use Absinthe.Schema

  alias UserRolesDemoWeb.GraphQL.Resolvers

  object :role do
    field :id, :id
    field :name, :string
    field :description, :string
    field :active, :boolean
  end

  object :user do
    field :id, :id
    field :name, :string
    field :email, :string
    field :is_active, :boolean
    field :roles, list_of(:role)
  end

  object :login_payload do
    field :token, :string
    field :user, :user
  end

  query do
    @desc "The currently authenticated user (requires Authorization: Bearer <token>)"
    field :me, :user do
      resolve(&Resolvers.Accounts.me/3)
    end

    @desc "Active roles"
    field :roles, list_of(:role) do
      resolve(&Resolvers.Accounts.roles/3)
    end
  end

  mutation do
    @desc "Authenticates with email + password and returns a Bearer token"
    field :login, :login_payload do
      arg(:email, non_null(:string))
      arg(:password, non_null(:string))
      resolve(&Resolvers.Accounts.login/3)
    end
  end
end
