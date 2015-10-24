module Proxi
  class Server
    include Wisper::Publisher

    MAX_CONNECTIONS = 5

    def initialize(listen_port, connection_factory)
      @connection_factory = connection_factory

      @server = TCPServer.new(nil, listen_port)

      @connections = []
    end

    def call
      loop do
        in_socket = @server.accept
        connection = @connection_factory.call(in_socket)

        broadcast(:new_connection, connection)

        @connections.push(connection)

        connection.call

        reap_connections
        while @connections.size >= MAX_CONNECTIONS
          sleep 1
          reap_connections
        end
      end
    end

    def reap_connections
      @connections = @connections.select do |t|
        if t.alive?
          true
        else
          t.join_thread
          false
        end
      end
    end
  end
end
