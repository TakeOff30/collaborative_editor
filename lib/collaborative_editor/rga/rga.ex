defmodule CollaborativeEditor.RGA do
  @moduledoc """
  This module implements a Replicated Growable Array (RGA) CRDT for collaborative text editing.
  Supports insertion and deletion of chars.
  """
  alias CollaborativeEditor.RGA.Element
  defstruct elements: %{}, head: nil

  @typedoc """
  The RGA document state, consisting of a map of elements and a reference to the head
  element (the starting point of the document).
  """
  @type t :: %__MODULE__{
    elements: %{{integer, any} => Element.t()},
    head: Element.t() | nil
  }

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec insert(t(), String.t(), {integer, any()} | nil, {integer, any()}) :: t()
  def insert(rga, char, predecessor_id, id) do
    new_element = %Element{id: id, char: char, deleted: false, predecessor_id: predecessor_id}
    updated_elements = Map.put(rga.elements, id, new_element)

    new_head =
      case {predecessor_id, rga.head} do
        {nil, nil} -> new_element
        {nil, current_head} -> if id > current_head.id, do: new_element, else: current_head
        _ -> rga.head
      end

    %__MODULE__{elements: updated_elements, head: new_head}
  end

  @spec delete(t(), {integer, any()}) :: t()
  def delete(rga, id) do
    case Map.get(rga.elements, id) do
      nil -> rga
      element ->
        updated_element = %Element{element | deleted: true}
        updated_elements = Map.put(rga.elements, id, updated_element)
        %__MODULE__{rga | elements: updated_elements}
    end
  end

  @spec to_string(t()) :: String.t()
  def to_string(rga) do
    successors_map =
      rga.elements
      |> Map.values()
      |> Enum.reject(fn element -> element.deleted end)
      |> Enum.group_by(fn element -> element.predecessor_id end)

    build_string(successors_map, nil)
  end

  @doc """
  Recursively builds the string representation of the RGA by traversing the elements.
  """
  @spec build_string(%{({integer, any()}) | nil => [Element.t()]}, ({integer, any()}) | nil) :: String.t()
  defp build_string(successors_map, predecessor_id) do
    successors = Map.get(successors_map, predecessor_id, [])

    sorted_successors = Enum.sort_by(successors, (fn element -> element.id end), (fn a, b -> a >= b end))

    Enum.reduce(sorted_successors, "", fn element, acc ->
      acc <> element.char <> build_string(successors_map, element.id)
    end)
  end

end
