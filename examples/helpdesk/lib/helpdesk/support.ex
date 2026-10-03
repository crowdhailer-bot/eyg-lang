defmodule Helpdesk.Support do
  use Ash.Domain, extensions: [AshEyg.Domain]

  resources do
    resource Helpdesk.Support.Ticket
    resource Helpdesk.Support.Representative
  end
end
