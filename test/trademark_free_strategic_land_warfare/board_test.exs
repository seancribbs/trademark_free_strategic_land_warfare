defmodule TrademarkFreeStrategicLandWarfare.BoardTest do
  use ExUnit.Case

  alias TrademarkFreeStrategicLandWarfare.{Board, Piece}

  def shuffled_pieces() do
    Board.piece_name_counts()
    |> Enum.flat_map(fn {type, count} ->
      for _ <- 1..count, do: type
    end)
    |> Enum.shuffle()
  end

  def good_piece_setup() do
    Enum.chunk_every(shuffled_pieces(), 10)
  end

  def bad_piece_setup() do
    [replace_this, with_this] =
      Board.piece_name_counts()
      |> Map.keys()
      |> Enum.shuffle()
      |> Enum.take(2)

    shuffled_pieces()
    |> Enum.map(fn piece ->
      case piece do
        ^replace_this -> with_this
        piece -> piece
      end
    end)
    |> Enum.chunk_every(4)
  end

  def placements_from_board(board, player) do
    board.rows
    |> Board.maybe_flip(player)
    |> Enum.drop(6)
    |> Enum.map(fn row ->
      Enum.map(row, fn column -> column.name end)
    end)
  end

  def setup_two_players() do
    Enum.reduce(1..2, Board.new(), fn player, board_acc ->
      placements = good_piece_setup()
      {:ok, new_board} = Board.init_pieces(board_acc, placements, player)
      new_board
    end)
  end

  def place_piece_at(name, index, player) do
    placements =
      shuffled_pieces()
      |> Kernel.--([name])
      |> List.insert_at(index, name)
      |> Enum.chunk_every(10)

    {:ok, board} = Board.init_pieces(Board.new(), placements, player)
    piece = Board.lookup_by_coord(board, {index, 6}, player)

    {board, piece}
  end

  def place_only(specs) do
    Enum.reduce(specs, {Board.new(), []}, fn {coord, piece}, {board, pieces} ->
      {:ok, new_board} = Board.place_piece(board, piece, coord, 1)
      {new_board, pieces ++ [piece]}
    end)
  end

  describe "piece_name_counts" do
    test "returns a hash with correct piece counts" do
      counts = Board.piece_name_counts()
      assert counts[:marshall] == 1
      assert counts[:miner] == 5
    end
  end

  describe "init_pieces" do
    test "for player 1, no flip necessary" do
      placements = good_piece_setup()
      {:ok, new_board} = Board.init_pieces(Board.new(), placements, 1)
      assert placements_from_board(new_board, 1) == placements
    end

    test "for player 2, flip the board to player perspective before inserting" do
      placements = good_piece_setup()
      {:ok, new_board} = Board.init_pieces(Board.new(), placements, 2)
      assert placements_from_board(new_board, 2) == placements
    end

    test "doesn't mess up previously placed pieces" do
      [player_1_placements, player_2_placements] = for _ <- 1..2, do: good_piece_setup()

      {:ok, board_with_player_1_placements} =
        Board.init_pieces(Board.new(), player_1_placements, 1)

      {:ok, board_with_player_2_placements} =
        Board.init_pieces(board_with_player_1_placements, player_2_placements, 2)

      assert placements_from_board(board_with_player_1_placements, 1) == player_1_placements
      assert placements_from_board(board_with_player_2_placements, 2) == player_2_placements
    end

    test "returns a board with 10 rows" do
      {:ok, new_board} = Board.init_pieces(Board.new(), good_piece_setup(), 2)
      assert length(new_board.rows) == 10
    end

    test "has lake pieces in the correct places" do
      {:ok, new_board} = Board.init_pieces(Board.new(), good_piece_setup(), 2)
      rows = new_board.rows

      for {x, y} <- [{2, 4}, {3, 4}, {6, 4}, {7, 4}, {2, 5}, {3, 5}, {6, 5}, {7, 5}] do
        assert get_in(rows, [Access.at(y), Access.at(x)]) == :lake
      end
    end

    test "can't pass incorrect piece counts" do
      assert {:error, _} = Board.init_pieces(Board.new(), bad_piece_setup(), 2)
    end

    test "can't pass something other than 4 rows of 10" do
      placements =
        good_piece_setup()
        |> List.flatten()
        |> Enum.chunk_every(11)

      assert {:error, _} = Board.init_pieces(Board.new(), placements, 2)
    end
  end

  describe "translate_coord" do
    test "for player 1, no translation for coord" do
      for coord <- [{4, 2}, {5, 8}, {9, 0}] do
        assert ^coord = Board.translate_coord(coord, 1)
      end
    end

    test "for player 2, translation to player perspective for coord" do
      assert {2, 7} = Board.translate_coord({7, 2}, 2)
      assert {4, 8} = Board.translate_coord({5, 1}, 2)
      assert {9, 1} = Board.translate_coord({0, 8}, 2)
    end
  end

  describe "lookup_by_uuid" do
    test "for player 1, no translation" do
      {:ok, %Board{rows: rows} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 1)

      for {row, y} <- rows |> Enum.drop(6) |> Enum.zip(6..9) do
        for {piece, x} <- Enum.zip(row, 0..9) do
          assert {{^x, ^y}, ^piece} = Board.lookup_by_uuid(board, piece.uuid, 1)
        end
      end
    end

    test "for player 2, perspective for lookup is translated" do
      {:ok, %Board{rows: rows} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 2)

      for {row, y} <- rows |> Enum.take(4) |> Enum.zip(0..3) do
        for {piece, x} <- Enum.zip(row, 0..9) do
          translated_x = 9 - x
          translated_y = 9 - y

          assert {{^translated_x, ^translated_y}, ^piece} =
                   Board.lookup_by_uuid(board, piece.uuid, 2)
        end
      end
    end

    test "returns nil when no piece is present with that name" do
      {:ok, %Board{} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 1)
      assert nil == Board.lookup_by_uuid(board, "my-bogus-id", 1)
    end
  end

  describe "lookup_by_coord" do
    test "for player 1, no translation" do
      {:ok, %Board{rows: rows} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 1)

      for {row, y} <- rows |> Enum.drop(6) |> Enum.zip(6..9) do
        for {piece, x} <- Enum.zip(row, 0..9) do
          assert ^piece = Board.lookup_by_coord(board, {x, y}, 1)
        end
      end
    end

    test "for player 2, perspective for lookup is translated" do
      {:ok, %Board{rows: rows} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 2)

      for {row, y} <- rows |> Enum.take(4) |> Enum.zip(0..3) do
        for {piece, x} <- Enum.zip(row, 0..9) do
          assert ^piece = Board.lookup_by_coord(board, {9 - x, 9 - y}, 2)
        end
      end
    end

    test "when coordinate is out of bounds, doesn't error" do
      {:ok, %Board{} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 2)
      assert nil == Board.lookup_by_coord(board, {10, 0}, 1)
    end
  end

  describe "remove_pieces" do
    test "removes multiple pieces" do
      {:ok, %Board{} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 1)

      pieces_to_remove =
        board.rows
        |> Enum.at(Enum.random(6..9))
        |> Enum.take(2)

      new_board = Board.remove_pieces(board, pieces_to_remove)

      all_uuids =
        new_board.rows
        |> List.flatten()
        |> Enum.filter(&is_struct(&1))
        |> Enum.map(& &1.uuid)

      for piece <- pieces_to_remove do
        assert nil == Board.lookup_by_uuid(new_board, piece.uuid)
        assert nil == Enum.find(all_uuids, &(&1 == piece.uuid))
      end
    end
  end

  describe "remove_piece" do
    test "removes a piece, if it exists" do
      {:ok, %Board{} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 1)

      piece_to_remove =
        board.rows
        |> Enum.at(Enum.random(6..9))
        |> Enum.at(Enum.random(0..9))

      new_board = Board.remove_piece(board, piece_to_remove)

      all_uuids =
        new_board.rows
        |> List.flatten()
        |> Enum.filter(&is_struct(&1))
        |> Enum.map(& &1.uuid)

      assert nil == Board.lookup_by_uuid(new_board, piece_to_remove.uuid)
      assert nil == Enum.find(all_uuids, &(&1 == piece_to_remove.uuid))
    end

    test "doesn't fail if a bogus uuid is passed" do
      {:ok, %Board{} = board} = Board.init_pieces(Board.new(), good_piece_setup(), 1)
      new_board = Board.remove_piece(board, Piece.new(:marshall, 1))
      assert board == new_board
    end
  end

  describe "place_piece" do
    test "place a piece on the board" do
      board = Board.new()
      piece = Piece.new(:spy, 1)
      coord = {1, 8}
      {:ok, new_board} = Board.place_piece(board, piece, coord)

      assert piece == Board.lookup_by_coord(new_board, coord)
      assert {coord, piece} == Board.lookup_by_uuid(new_board, piece.uuid)
    end

    test "place a piece on the board for player 2 translates coordinate" do
      board = Board.new()
      piece = Piece.new(:flag, 2)
      coord = {3, 1}
      {:ok, new_board} = Board.place_piece(board, piece, coord, 2)

      assert piece == Board.lookup_by_coord(new_board, {6, 8})
      assert {{6, 8}, piece} == Board.lookup_by_uuid(new_board, piece.uuid)
    end

    test "place a piece on the board removes the piece from previous location" do
      board = Board.new()
      piece = Piece.new(:spy, 2)
      initial_coord = {2, 2}
      {:ok, initial_board} = Board.place_piece(board, piece, initial_coord, 2)

      new_coord = {2, 3}
      {:ok, new_board} = Board.place_piece(initial_board, piece, new_coord, 2)

      assert nil == Board.lookup_by_coord(new_board, {7, 7})
      assert piece == Board.lookup_by_coord(new_board, {7, 6})
      assert {{7, 6}, piece} == Board.lookup_by_uuid(new_board, piece.uuid)
    end

    test "won't place a piece where a lake is" do
      board = Board.new()
      piece = Piece.new(:flag, 1)
      initial_coord = {3, 5}

      assert {:error, "can't place a piece where a lake is"} =
               Board.place_piece(board, piece, initial_coord, 1)
    end

    test "won't place a piece out of bounds" do
      board = Board.new()
      piece = Piece.new(:scout, 1)
      initial_coord = {11, 6}

      assert {:error, "can't place a piece out of bounds"} =
               Board.place_piece(board, piece, initial_coord, 1)
    end
  end

  describe "maybe_flip" do
    test "no action when player 1" do
      {:ok, %Board{rows: rows}} = Board.init_pieces(Board.new(), good_piece_setup(), 1)
      assert Board.maybe_flip(rows, 1) == rows
    end

    test "flips perspective when player 2" do
      {:ok, %Board{rows: rows}} = Board.init_pieces(Board.new(), good_piece_setup(), 2)
      flipped_rows = Board.maybe_flip(rows, 2)

      assert rows != flipped_rows

      assert get_in(rows, [Access.at(1), Access.at(6)]) ==
               get_in(flipped_rows, [Access.at(8), Access.at(3)])
    end
  end

  describe "move" do
    test "successfully moves to an empty space" do
      {board, piece} = place_piece_at(:marshall, 0, 1)
      {:ok, new_board} = Board.move(board, 1, piece.uuid, :forward, 1)
      assert {{0, 5}, piece} == Board.lookup_by_uuid(new_board, piece.uuid, 1)
    end

    test "errors when trying to move to a lake" do
      {board, piece} = place_piece_at(:miner, 7, 2)

      assert {:error, "can't place a piece where a lake is"} ==
               Board.move(board, 2, piece.uuid, :forward, 1)
    end

    test "errors when trying to move outside of bounds" do
      {board, piece} = place_piece_at(:spy, 0, 2)

      assert {:error, "can't place a piece out of bounds"} ==
               Board.move(board, 2, piece.uuid, :left, 1)
    end

    test "returns an error if other player's piece is attempted to be moved" do
      {board, piece} = place_piece_at(:major, 4, 1)

      assert {:error, "you cannot move the other player's piece"} ==
               Board.move(board, 2, piece.uuid, :forward, 1)
    end

    test "disallows moving a piece that, doesn't exist on the board" do
      board = setup_two_players()

      assert {:error, "no piece with that name"} ==
               Board.move(board, 2, "my-bogus-uuid-here", :forward, 2)
    end

    test "disallows moving a bomb" do
      {board, piece} = place_piece_at(:bomb, 9, 2)
      assert {:error, "bombs cannot move"} == Board.move(board, 2, piece.uuid, :forward, 1)
    end

    test "disallows moving a flag" do
      {board, piece} = place_piece_at(:flag, 2, 1)
      assert {:error, "flags cannot move"} == Board.move(board, 1, piece.uuid, :forward, 1)
    end

    test "allows moving a scout more than 1 square, if open, and reveals the piece" do
      {board, piece} = place_piece_at(:scout, 1, 2)
      {:ok, new_board} = Board.move(board, 2, piece.uuid, :forward, 6)

      assert {{1, 0}, %Piece{piece | visible: true}} ==
               Board.lookup_by_uuid(new_board, piece.uuid, 2)
    end

    test "stops a scout if they hit an opponent piece (attacking logic included here)" do
      {board, piece} = place_piece_at(:scout, 0, 1)
      opponent_piece = Piece.new(:spy, 2)
      {:ok, board_with_opponent_piece} = Board.place_piece(board, opponent_piece, {9, 6}, 2)
      {:ok, new_board} = Board.move(board_with_opponent_piece, 1, piece.uuid, :forward, 6)

      assert {{0, 3}, %Piece{piece | visible: true}} ==
               Board.lookup_by_uuid(new_board, piece.uuid, 1)
    end

    test "a scout errors if it hits its own piece" do
      {board, [scout, _]} =
        place_only([
          {{4, 3}, Piece.new(:scout, 2)},
          {{4, 0}, Piece.new(:marshall, 2)}
        ])

      assert {:error, "you can't run into your own team's piece"} =
               Board.move(board, 2, scout.uuid, :backward, 6)
    end

    test "a scout errors if it hits a barrier" do
      {board, [scout]} =
        place_only([
          {{4, 3}, Piece.new(:scout, 1)}
        ])

      assert {:error, "can't place a piece out of bounds"} =
               Board.move(board, 1, scout.uuid, :right, 6)
    end

    test "reveals either the attacker and defender if an attack happens and a piece remains" do
      {board, [bomb, captain]} =
        place_only([
          {{7, 2}, Piece.new(:bomb, 1)},
          {{8, 2}, Piece.new(:captain, 2)}
        ])

      assert {:ok, attack_finished_board} = Board.move(board, 2, captain.uuid, :right, 1)

      assert nil == Board.lookup_by_uuid(attack_finished_board, captain.uuid, 2)

      assert {{7, 2}, %Piece{bomb | visible: true}} ==
               Board.lookup_by_uuid(attack_finished_board, bomb.uuid, 1)
    end

    test "returns a win if piece moves onto opponent flag" do
      {board, [_, major]} =
        place_only([
          {{2, 9}, Piece.new(:flag, 1)},
          {{2, 8}, Piece.new(:major, 2)}
        ])

      assert {:ok, :win} = Board.move(board, 2, major.uuid, :forward, 1)
    end

    test "errors when piece attacks piece of the same player" do
      {board, [_, colonel]} =
        place_only([
          {{3, 9}, Piece.new(:spy, 1)},
          {{4, 9}, Piece.new(:colonel, 1)}
        ])

      assert {:error, "you can't run into your own team's piece"} =
               Board.move(board, 1, colonel.uuid, :left, 1)
    end

    test "removes the attacking piece if loses battle" do
      {board, [general, major]} =
        place_only([
          {{3, 9}, Piece.new(:general, 1)},
          {{4, 9}, Piece.new(:major, 2)}
        ])

      assert {:ok, attack_finished_board} = Board.move(board, 2, major.uuid, :right, 1)

      assert {{3, 9}, %Piece{general | visible: true}} ==
               Board.lookup_by_uuid(attack_finished_board, general.uuid, 1)
    end

    test "removes the defending piece if loses battle" do
      {board, [_, miner]} =
        place_only([
          {{3, 9}, Piece.new(:bomb, 1)},
          {{3, 8}, Piece.new(:miner, 2)}
        ])

      assert {:ok, attack_finished_board} = Board.move(board, 2, miner.uuid, :forward, 1)

      assert {{3, 9}, %Piece{miner | visible: true}} ==
               Board.lookup_by_uuid(attack_finished_board, miner.uuid, 1)
    end

    test "removes both the attacking and defending piece if ties battle" do
      {board, [captain1, captain2]} =
        place_only([
          {{9, 0}, Piece.new(:captain, 1)},
          {{9, 1}, Piece.new(:captain, 2)}
        ])

      assert {:ok, attack_finished_board} = Board.move(board, 1, captain1.uuid, :backward, 1)

      assert nil == Board.lookup_by_uuid(attack_finished_board, captain1.uuid, 1)
      assert nil == Board.lookup_by_uuid(attack_finished_board, captain2.uuid, 1)
    end

    test "errors if any piece other than a scout attempts to go more than 1 space" do
      {board, piece} = place_piece_at(:miner, 1, 1)

      assert {:error, "all pieces except the scout can only advance 1"} ==
               Board.move(board, 1, piece.uuid, :forward, 2)
    end
  end

  describe "maybe_invert_player_direction" do
    test "same for player 1" do
      directions = [:forward, :backward, :right, :left]

      assert directions ==
               for(direction <- directions, do: Board.maybe_invert_player_direction(direction, 1))
    end

    test "inverts for player 2" do
      directions = [:forward, :backward, :right, :left]

      assert [:backward, :forward, :left, :right] ==
               for(direction <- directions, do: Board.maybe_invert_player_direction(direction, 2))
    end
  end

  describe "new_coordinate" do
    test "moves forward" do
      assert {2, 0} == Board.new_coordinate({2, 1}, :forward)
    end

    test "moves backward" do
      assert {8, 8} == Board.new_coordinate({8, 7}, :backward)
    end

    test "moves left" do
      assert {4, 5} == Board.new_coordinate({5, 5}, :left)
    end

    test "moves right" do
      assert {8, 2} == Board.new_coordinate({7, 2}, :right)
    end
  end

  describe "mask_board" do
    test "for the player whose piece it is, pieces aren't masked" do
      {board, [flag, major]} =
        place_only([
          {{9, 0}, Piece.new(:flag, 1)},
          {{9, 1}, Piece.new(:major, 2)}
        ])

      board_for_player_1 = Board.mask_board(board, 1)
      board_for_player_2 = Board.mask_board(board, 2)
      assert board_for_player_1 != board_for_player_2

      assert {{9, 0}, %Piece{name: :flag, rank: nil, lose_when_attacked_by: nil}} =
               Board.lookup_by_uuid(board_for_player_1, flag.uuid, 1)

      assert {{9, 1}, %Piece{name: nil, rank: nil, lose_when_attacked_by: nil}} =
               Board.lookup_by_uuid(board_for_player_1, major.uuid, 1)
    end

    test "when marked visible, the piece is revealed to the opponent" do
      {board, [flag, major]} =
        place_only([
          {{9, 0}, Piece.new(:flag, 1)},
          {{9, 1}, :major |> Piece.new(2) |> Piece.reveal()}
        ])

      board_for_player_1 = Board.mask_board(board, 1)
      board_for_player_2 = Board.mask_board(board, 2)
      assert board_for_player_1 != board_for_player_2

      assert {{9, 0}, %Piece{name: :flag, rank: nil, lose_when_attacked_by: nil}} =
               Board.lookup_by_uuid(board_for_player_1, flag.uuid, 1)

      assert {{9, 1}, %Piece{name: :major, rank: 7, lose_when_attacked_by: nil}} =
               Board.lookup_by_uuid(board_for_player_1, major.uuid, 1)
    end
  end

  # describe "new" do

  #  test "fails when no name is passed" do
  #    assert_raise RuntimeError, ~r/^player must have a name!$/, fn ->
  #      Player.new(nil, 1)
  #    end
  #  end

  #  test "creates a new player will work for player 1 or 2" do
  #    name = ThisPlayer

  #    for n <- 1..2 do
  #      assert %Player{player: ^n, name: ^name} = Player.new(name, n)
  #    end
  #  end

  #  test "create a new player won't work for players outside that range" do
  #    assert_raise RuntimeError, ~r/^player valid range is 1-2!$/, fn ->
  #      Player.new(WhichPlayer, 3)
  #    end
  #  end
  # end
end
