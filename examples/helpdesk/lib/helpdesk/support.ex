defmodule Helpdesk.Support do
  use Ash.Domain, extensions: [AshEyg.Domain, AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Helpdesk.Support.Ticket
    resource Helpdesk.Support.Representative
  end
end
