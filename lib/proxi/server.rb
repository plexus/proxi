# ## Proxi::Server
#
module Proxi

  # `Proxi::Server` accepts TCP requests, and forwards them, by creating an
  # outbound connection and forwarding traffic in both directions.
  #
  # The destination of the outbound connection, and the forwarding of data, is
  # handled by a `Proxi::Connection`, created by a factory object, which can be a
  # lambda.
  #
  # Start listening for connections by calling #call.
  #
  # `Proxi::Server` broadcasts the following events:
  #
  # - `new_connection(Proxi::Connection)`
  # - `dead_connection(Proxi::Connection)`
  class Server
    include Wisper::Publisher

    # Public: Initialize a Server
    #
    # listen_port        - The String or Integer of the port to listen to for
    #                      incoming connections
    # connection_factory - Implements #call(in_socket) and returns a
    #                      Proxi::Connection
    # max_connections    - The maximum amount of parallel connections to handle
    #                      at once
    def initialize(listen_port, connection_factory, max_connections: 5)
      @listen_port = listen_port
      @connection_factory = connection_factory
      @max_connections = 5
      @connections = []
    end

    # Public: Start the server
    #
    # Start accepting and forwarding requests
    def call
      @server = TCPServer.new('localhost', @listen_port)

      until @server.closed?
        in_socket = @server.accept
        connection = @connection_factory.call(in_socket)

        broadcast(:new_connection, connection)

        @connections.push(connection)

        connection.call # spawns a new thread that handles proxying

        reap_connections
        while @connections.size >= @max_connections
          sleep 1
          reap_connections
        end
      end
    ensure
      close
    end

    # Public: close the TCP server socket
    #
    # Included for completeness, note that if the proxy server is active it will
    # likely be blocking on TCPServer#accept, and the server port will stay open
    # until it has accepted one final request.
    def close
      @server.close if @server && !@server.closed?
    end

    private

    def reap_connections
      @connections = @connections.select do |conn|
        if conn.alive?
          true
        else
          broadcast(:dead_connection, conn)
          conn.join_thread
          false
        end
      end
    end
  end
end
