defmodule Dogmatix.ServiceCheck do
  @moduledoc """
  The struct to define a service check.
  """

  @enforce_keys [:name, :status]

  defstruct [
    :name,
    :status,
    :timestamp,
    :hostname,
    :message
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          status: :ok | :warning | :critical | :unknown,
          timestamp: integer() | DateTime.t() | nil,
          hostname: String.t() | nil,
          message: String.t() | nil
        }
end
