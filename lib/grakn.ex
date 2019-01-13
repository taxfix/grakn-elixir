defmodule Grakn do
  @moduledoc """
  The main entry point for interacting with Grakn. All functions take a
  connection reference.
  """

  @typedoc """
  A connection process name, pid or reference.
  A connection reference is used when making multiple requests within a
  transaction, see `transaction/3`.
  """
  @type conn :: DBConnection.conn()

  @doc """
  Start and link to a Grakn connnection process.

  ### Options
    * `:hostname` - The hostname of the Grakn server to connect to (required)
    * `:port` - The port of the Grakn server (default: 48555)
  """
  @spec start_link(Keyword.t()) :: {:ok, conn()} | {:error, any}
  def start_link(opts \\ []) do
    DBConnection.start_link(Grakn.Protocol, opts)
  end

  @doc """
  Execute a query on the connection process. Queries can anly be run run within
  a transaction, see `transaction/3`.

  ### Options
    * `:include_inferences` - Boolean specifying if inferences should be
      included in the querying process (default: true)
  """
  @spec query(conn(), Grakn.Query.t(), Keyword.t()) :: any()
  def query(conn, query, opts \\ []) do
    DBConnection.execute(conn, query, [], opts)
  end

  @doc """
  Execute a query on the connection process and raise an exception if there is
  an error. See `query/3` for documentation.
  """
  @spec query!(conn(), Grakn.Query.t(), Keyword.t()) :: any()
  def query!(conn, %Grakn.Query{} = query, opts \\ []) do
    DBConnection.execute!(conn, query, [], opts)
  end

  @spec command(conn(), Grakn.Command.t(), Keyword.t()) :: any()
  def command(conn, %Grakn.Command{} = command, opts \\ []) do
    DBConnection.execute(conn, command, [], opts)
  end

  @doc """
  Create a new transaction and execute a sequence of statements within the
  context of the transaction.

  ### Options
    * `:type` - The type of transaction, value must be
      `Grakn.Transaction.Type.read()` (default), or
      `Grakn.Transaction.Type.write()`

  ### Example
  ```
  Grakn.transaction(
    conn,
    fn conn ->
      Grakn.query(conn, Grakn.Query.graql("match $x isa Person; get;"))
    end
  )
  ```
  """
  @spec transaction(conn(), (conn() -> result), Keyword.t()) :: {:ok, result} | {:error, any}
        when result: var
  defdelegate transaction(conn, fun, opts \\ []), to: DBConnection

  @doc """
  Rollback a transaction, does not return.
  Aborts the current transaction fun. If inside multiple `transaction/3`
  functions, bubbles up to the top level.
  ## Example
      {:error, :oops} = Grakn.transaction(pid, fn(conn) ->
        Grakn.rollback(conn, :oops)
        IO.puts "never reaches here!"
      end)
  """
  @spec rollback(DBConnection.t(), any) :: no_return()
  defdelegate rollback(conn, any), to: DBConnection

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end
end
