defmodule CollaborativeEditor.RGA.Test do
  use ExUnit.Case, async: true

  alias CollaborativeEditor.RGA
  

  describe "new/0" do
    test "creates a new, empty RGA struct" do
      rga = RGA.new()
      assert rga == %RGA{elements: %{}, head: nil}
      assert RGA.to_string(rga) == ""
    end
  end

  describe "insert/4 and to_string/1" do
    test "handles sequential insertions correctly" do
      rga = RGA.new()
      # Insert "H" at the beginning
      rga = RGA.insert(rga, "H", nil, {1, :peer_a})
      assert RGA.to_string(rga) == "H"

      # Insert "i" after "H"
      rga = RGA.insert(rga, "i", {1, :peer_a}, {2, :peer_a})
      assert RGA.to_string(rga) == "Hi"
    end

    test "handles concurrent insertions by sorting on ID" do
      # 1. Start with "ac"
      rga = RGA.new()
      rga = RGA.insert(rga, "a", nil, {1, :peer_a})
      rga = RGA.insert(rga, "c", {1, :peer_a}, {2, :peer_a})
      assert RGA.to_string(rga) == "ac"

      # 2. Concurrently insert "b" and "X" after "a"
      # Peer A inserts "b" with a higher clock
      rga = RGA.insert(rga, "b", {1, :peer_a}, {4, :peer_a})
      # Peer B inserts "X" with a lower clock
      rga = RGA.insert(rga, "X", {1, :peer_a}, {3, :peer_b})

      # Expected order is "abXc" because "b" has a higher ID ({4, :peer_a})
      # and should be placed first after "a".
      assert RGA.to_string(rga) == "abXc"
    end

    test "handles concurrent insertions with same clock by sorting on peer_id" do
      # 1. Start with "ac"
      rga = RGA.new()
      rga = RGA.insert(rga, "a", nil, {1, :peer_a})
      rga = RGA.insert(rga, "c", {1, :peer_a}, {2, :peer_a})
      assert RGA.to_string(rga) == "ac"

      # 2. Concurrently insert "b" and "X" after "a" with the same clock
      # Peer B's ID is lexicographically larger than Peer A's
      rga = RGA.insert(rga, "b", {1, :peer_a}, {3, :peer_a})
      rga = RGA.insert(rga, "X", {1, :peer_a}, {3, :peer_b})

      # Expected order is "aXbc" because "peer_b" > "peer_a", so "X" wins.
      assert RGA.to_string(rga) == "aXbc"
    end
  end

  describe "delete/2" do
    test "marks an element as deleted and removes it from the string" do
      rga = RGA.new()
      rga = RGA.insert(rga, "H", nil, {1, :peer_a})
      rga = RGA.insert(rga, "i", {1, :peer_a}, {2, :peer_a})
      assert RGA.to_string(rga) == "Hi"

      rga = RGA.delete(rga, {2, :peer_a})
      assert RGA.to_string(rga) == "H"

      # Verify the element is marked as a tombstone
      deleted_element = rga.elements[{2, :peer_a}]
      assert deleted_element.deleted == true
    end

    test "is idempotent" do
      rga = RGA.new()
      rga = RGA.insert(rga, "a", nil, {1, :peer_a})

      # Delete once
      rga_after_one_delete = RGA.delete(rga, {1, :peer_a})
      assert RGA.to_string(rga_after_one_delete) == ""

      # Delete again
      rga_after_two_deletes = RGA.delete(rga_after_one_delete, {1, :peer_a})
      assert rga_after_one_delete == rga_after_two_deletes
    end

    test "does nothing when deleting a non-existent element" do
      rga = RGA.new()
      rga = RGA.insert(rga, "a", nil, {1, :peer_a})

      unchanged_rga = RGA.delete(rga, {99, :peer_x})
      assert rga == unchanged_rga
    end
  end
end
