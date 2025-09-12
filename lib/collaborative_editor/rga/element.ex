defmodule CollaborativeEditor.RGA.Element do
  @moduledoc """
  Represents an element in the RGA, which is a character with a unique ID,
  a deletion tombstone, and a reference to its predecessor element.
  """
  @enforce_keys [:id, :char, :deleted, :predecessor_id]

  @typedoc """
  Unique identifier for an element represented as a tuple {logical_clock, node_id}.
  """
  @type id :: {integer, any()}
  @type t :: %__MODULE__{
    id: id(),
    char: String.t() | nil,
    deleted: boolean(),
    predecessor_id: id() | nil
  }
  defstruct id: nil, char: nil, deleted: false, predecessor_id: nil

end
