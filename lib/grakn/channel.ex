defmodule Grakn.Channel do
  @moduledoc false

  alias Grakn.{Cache, Transaction}

  @opaque t :: GRPC.Channel.t()

  @ping_rate :timer.minutes(5)
  @default_session_ttl :timer.minutes(30)

  @spec open(String.t()) :: {:ok, t()} | {:error, any()}
  def open(uri) do
    GRPC.Stub.connect(uri, adapter_opts: %{http2_opts: %{keepalive: @ping_rate}})
  end

  @spec open_transaction(t(), Transaction.request()) ::
          {:ok, t(), Grakn.Transaction.t(), String.t()} | {:error, any()}
  def open_transaction(channel, %Transaction{type: type, opts: opts} = tx_request) do
    case fetch_or_open_session(channel, tx_request) do
      {:ok, {session_id, cached?}} ->
        with {:ok, tx} <- Grakn.Transaction.new(channel, opts),
             {:ok, tx} <- Transaction.open(tx, session_id, type, opts) do
          {:ok, channel, tx, session_id}
        else
          error ->
            maybe_reopen_transaction(channel, tx_request, error, cached?)
        end

      error ->
        maybe_reopen_transaction(channel, tx_request, error, false)
    end
  end

  defp maybe_reopen_transaction(channel, tx_request, error, cached?) do
    %{keyspace: keyspace, conn_opts: conn_opts} = tx_request

    with {:error, %GRPC.RPCError{message: message}} when is_binary(message) <- error do
      cond do
        cached? and (message =~ ~r/closed/ or message =~ ~r/null\..*/) ->
          # If session was closed by grakn, so we remove it from the cache and try again
          Cache.delete({:keyspace, keyspace})
          open_transaction(channel, tx_request)

        message =~ ~r/:noproc/ ->
          connection_uri = Grakn.connection_uri(conn_opts)
          with {:ok, channel} <- open(connection_uri), do: open_transaction(channel, tx_request)

        true ->
          error
      end
    end
  end

  defp fetch_or_open_session(channel, %{name: nil} = tx_request),
    do: open_session(channel, tx_request)

  defp fetch_or_open_session(channel, %{keyspace: keyspace, name: name} = tx_request) do
    case Cache.fetch({:keyspace, keyspace}) do
      %{session_id: session_id} ->
        Cache.touch({:keyspace, keyspace})
        {:ok, {session_id, true}}

      nil ->
        with {:ok, {session_id, cached?}} <- open_session(channel, tx_request) do
          session_ttl = Application.get_env(:grakn, :session_ttl, @default_session_ttl)
          Cache.put({:keyspace, keyspace}, %{session_id: session_id, name: name}, session_ttl)
          {:ok, {session_id, cached?}}
        end
    end
  end

  def open_session(channel, tx_request) do
    %{keyspace: keyspace, username: username, password: password, opts: opts} = tx_request
    req_opts = [Keyspace: keyspace, username: username, password: password]
    req = Session.Session.Open.Req.new(req_opts)
    do_open_session(channel, req, opts, nil, 2)
  end

  defp do_open_session(_channel, _req, _opts, last_error, 0), do: {:error, last_error}

  defp do_open_session(channel, req, opts, _last_error, attempts) do
    case Session.SessionService.Stub.open(channel, req, opts) do
      {:error, %GRPC.RPCError{message: _, status: 2} = error} ->
        do_open_session(channel, req, opts, error, attempts - 1)

      {:error, error} ->
        {:error, error}

      {:ok, %{sessionId: session_id}} ->
        {:ok, {session_id, false}}
    end
  end

  @spec command(t(), Grakn.Command.command(), keyword(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def command(channel, %Grakn.Command{command: :get_keyspaces} = cmd, _, opts) do
    request = Keyspace.Keyspace.Retrieve.Req.new()

    case Keyspace.KeyspaceService.Stub.retrieve(channel, request, opts) do
      {:ok, %Keyspace.Keyspace.Retrieve.Res{names: names}} ->
        {:ok, cmd, names}

      {:error, reason} ->
        {:error, reason}

      resp ->
        {:error, "Unexpected response from service #{inspect(resp)}"}
    end
  end

  def command(channel, %Grakn.Command{command: :create_keyspace} = cmd, [name: name], opts) do
    request = Keyspace.Keyspace.Create.Req.new(name: name)

    case Keyspace.KeyspaceService.Stub.create(channel, request, opts) do
      {:ok, %Keyspace.Keyspace.Create.Res{}} -> {:ok, cmd, nil}
      error -> error
    end
  end

  def command(channel, %Grakn.Command{command: :delete_keyspace} = cmd, [name: name], opts) do
    request = Keyspace.Keyspace.Delete.Req.new(name: name)

    case Keyspace.KeyspaceService.Stub.delete(channel, request, opts) do
      {:ok, %Keyspace.Keyspace.Delete.Res{}} -> {:ok, cmd, nil}
      error -> error
    end
  end

  def command(channel, %Grakn.Command{command: :close_session}, [session_id: session_id], opts) do
    close_session(channel, session_id, opts)
  end

  @spec may_close_session(t(), String.t(), atom(), Keyword.t()) ::
          {:ok, :ignore} | {:ok, Session.Session.Close.Res.t()} | {:error, any()}
  def may_close_session(channel, session_id, nil, opts),
    do: close_session(channel, session_id, opts)

  def may_close_session(_channel, _session_id, _name, _opts), do: {:ok, :ignore}

  @spec close_session(t(), String.t(), Keyword.t()) ::
          {:ok, Session.Session.Close.Res.t()} | {:error, any()}
  def close_session(channel, session_id, opts) do
    session_id = Session.Session.Close.Req.new(sessionId: session_id)
    Session.SessionService.Stub.close(channel, session_id, opts)
  end

  @spec close(t()) :: :ok
  def close(channel) do
    GRPC.Stub.disconnect(channel)
    :ok
  end
end
