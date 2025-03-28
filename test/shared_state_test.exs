defmodule SharedStateTest do
  use ExUnit.Case
  import Chorex

  defmodule MultiBuyer do
    defchor [BookBuyer, BookSeller] do
      def run(BookSeller.(warehouse)) do
        BookBuyer.get_title() ~> BookSeller.(title)
        BookSeller.get_price(title) ~> BookBuyer.(item_price)
        if BookBuyer.in_budget?(item_price), notify: [BookSeller] do
          with BookSeller.(reserved?) <- BookSeller.reserve_item(title, warehouse) do
            if BookSeller.(reserved?), notify: [BookBuyer] do
              BookSeller.compute_shipping() ~> BookBuyer.(arrival)
              BookBuyer.({:got_it, item_price, arrival})
            else
              BookBuyer.(:missed_it)
            end
          end
        else
          BookBuyer.(:too_expensive)
        end
      end
    end
  end

  # This is not an actor in the choreography; it's just a way to synchronize book sales
  defmodule BookWarehouse do
    use GenServer

    def init(_) do
      {:ok, %{"Anathem" => 1, "Knights of Wind and Truth" => 42}}
    end

    def handle_call({:reserve, title}, _caller, state) do
      if state[title] && state[title] > 0 do
        new_state = Map.update(state, title, 0, fn x -> x - 1 end)
        {:reply, true, new_state}
      else
        {:reply, false, state}
      end
    end

    def reserve(server, title) do
      GenServer.call(server, {:reserve, title})
    end
  end

  defmodule MyBookBuyer do
    use MultiBuyer.Chorex, :bookbuyer

    @impl true
    def get_title(), do: "Anathem"
    @impl true
    def in_budget?(_price), do: true
  end

  defmodule MyBookSeller do
    use MultiBuyer.Chorex, :bookseller

    @impl true
    def compute_shipping(), do: "tomorrow"
    @impl true
    def get_price(_title), do: 42

    @impl true
    def reserve_item(book_title, warehouse) do
      BookWarehouse.reserve(warehouse, book_title)
    end
  end

  test "one buyer successful" do
    {:ok, warehouse} = GenServer.start_link(BookWarehouse, nil)

    Chorex.start(MultiBuyer.Chorex,
                 %{BookBuyer => MyBookBuyer,
                 BookSeller => MyBookSeller},
                 [warehouse])

    assert_receive {:chorex_return, BookBuyer, {:got_it, 42, "tomorrow"}}
    refute_receive {:chorex_return, BookBuyer, :missed_it}
  end

  # This test shows that only one buyer can get the book (Anathem).
  # The Warehouse GenServer that MyBookSeller communicates with
  # ensures that there is no double-selling of a particular book.
  test "two buyers: only one successful" do
    {:ok, warehouse} = GenServer.start_link(BookWarehouse, nil)

    Chorex.start(MultiBuyer.Chorex,
                 %{BookBuyer => MyBookBuyer,
                 BookSeller => MyBookSeller},
                 [warehouse])

    Chorex.start(MultiBuyer.Chorex,
                 %{BookBuyer => MyBookBuyer,
                 BookSeller => MyBookSeller},
                 [warehouse])

    assert_receive {:chorex_return, BookBuyer, {:got_it, 42, "tomorrow"}}
    refute_receive {:chorex_return, BookBuyer, {:got_it, 42, "tomorrow"}} # didn't get it a second time
    assert_receive {:chorex_return, BookBuyer, :missed_it}
  end
end
