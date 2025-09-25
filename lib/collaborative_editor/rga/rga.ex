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
    IO.puts(inspect(new_element))
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
      nil ->
        rga

      element ->
        updated_element = %Element{element | deleted: true}
        updated_elements = Map.put(rga.elements, id, updated_element)
        %__MODULE__{rga | elements: updated_elements}
    end
  end

  @spec id_at_position(t(), integer()) :: {integer, any} | nil
  def id_at_position(rga, position) do
    list = to_list(rga)

    if position < 1 or position > Enum.count(list) do
      nil
    else
      Enum.at(list, position - 1).id
    end
  end

  @spec position_of_id(t(), Element.id()) :: integer() | nil
  def position_of_id(rga, id) do
    case Enum.find_index(to_list(rga), &(&1.id == id)) do
      nil -> nil
      index -> index + 1
    end
  end

  @spec to_list(t()) :: list(Element.t())
  def to_list(rga) do
    successors_map =
      rga.elements
      |> Map.values()
      |> Enum.group_by(fn element -> element.predecessor_id end)

    build_list_from_map(successors_map, nil)
  end

  defp build_list_from_map(successors_map, predecessor_id) do
    successors = Map.get(successors_map, predecessor_id, [])
    sorted_successors = Enum.sort(successors, fn a, b -> a.id > b.id end)

    Enum.flat_map(sorted_successors, fn element ->
      non_deleted_part = if element.deleted, do: [], else: [element]
      rest = build_list_from_map(successors_map, element.id)
      non_deleted_part ++ rest
    end)
  end

  @spec to_string(t()) :: String.t()
  def to_string(rga) do
    rga
    |> to_list()
    |> Enum.map_join("", fn element -> element.char end)
  end
end
