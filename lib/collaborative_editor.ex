defmodule CollaborativeEditor do
  @moduledoc """
  CollaborativeEditor implements a distributed collaborative text editor
  using Conflict-free Replicated Data Types (CRDTs) and causal broadcast
  for real-time collaboration without conflicts.

  The core components include:
  - RGA (Replicated Growable Array) CRDT for text operations
  - Peer processes for managing individual user sessions
  - Registry for peer discovery and management
  - Causal broadcast for message ordering
  """
end
