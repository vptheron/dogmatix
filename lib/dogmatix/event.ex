defmodule Dogmatix.Event do
  @moduledoc """
  The struct to define an event.
  """

  @enforce_keys [:title, :text]

  defstruct [
    :title,
    :text,
    :timestamp,
    :hostname,
    :priority,
    :alert_type
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          text: String.t(),
          timestamp: integer() | DateTime.t() | nil,
          hostname: String.t() | nil,
          priority: :normal | :low | nil,
          alert_type: :error | :warning | :info | :success | nil
        }
end
