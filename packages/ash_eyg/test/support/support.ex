defmodule AshEyg.Test.Support do
  @moduledoc false
  use Ash.Domain, extensions: [AshEyg.Domain], validate_config_inclusion?: false

  resources do
    resource AshEyg.Test.Ticket
    resource AshEyg.Test.Note
  end
end

defmodule AshEyg.Test.Ticket do
  @moduledoc false
  use Ash.Resource,
    domain: AshEyg.Test.Support,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshEyg.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :priority, :integer, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:open, :closed]],
      default: :open,
      allow_nil?: false,
      public?: true

    attribute :secret, :string
  end

  actions do
    defaults [:read, :destroy]

    create :open do
      accept [:subject, :priority]
    end

    update :close do
      change set_attribute(:status, :closed)
    end

    read :by_status do
      argument :status, :atom, constraints: [one_of: [:open, :closed]], allow_nil?: false
      filter expr(status == ^arg(:status))
    end

    action :count, :integer do
      run fn _input, context ->
        {:ok, __MODULE__ |> Ash.read!(Ash.Context.to_opts(context)) |> length()}
      end
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end
end

defmodule AshEyg.Test.Note do
  @moduledoc false
  use Ash.Resource,
    domain: AshEyg.Test.Support,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshEyg.Resource]

  eyg do
    expose?(false)
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
  end
end
