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

  @spec to_list(t()) :: list(Element.t())
  def to_list(rga) do
    successors_map =
      rga.elements
      |> Map.values()
      |> Enum.group_by(fn element -> element.predecessor_id end)

    build_list_filtered(successors_map, nil)
  end

  @spec build_list_filtered(map(), {integer, any}) :: list(Element.t())
  defp build_list_filtered(successors_map, predecessor_id) do
    successors = Map.get(successors_map, predecessor_id, [])

    sorted_successors =
      Enum.sort_by(successors, fn element -> element.id end, fn a, b -> a >= b end)

    Enum.flat_map(sorted_successors, fn element ->
      non_deleted_part = if element.deleted, do: [], else: [element]

      rest = build_list_filtered(successors_map, element.id)

      non_deleted_part ++ rest
    end)
  end

  @spec to_string(t()) :: String.t()
  def to_string(rga) do
    successors_map =
      rga.elements
      |> Map.values()
      |> Enum.group_by(fn element -> element.predecessor_id end)

    build_string(successors_map, nil, rga.elements)
  end

  @spec build_string(map(), {any(), integer}, map()) :: String.t()
  defp build_string(successors_map, predecessor_id, elements) do
    successors = Map.get(successors_map, predecessor_id, [])

    sorted_successors =
      Enum.sort_by(successors, fn element -> element.id end, fn a, b -> a >= b end)

    Enum.reduce(sorted_successors, "", fn element, acc ->
      if Map.get(elements, element.id).deleted do
        acc <> build_string(successors_map, element.id, elements)
      else
        acc <> element.char <> build_string(successors_map, element.id, elements)
      end
    end)
  end
end
