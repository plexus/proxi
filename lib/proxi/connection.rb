# ## Proxi::Connection
#
module Proxi

  # A `Connection` is a bidirectional pipe between two sockets.
  #
  # The proxy server hands it the socket for the incoming request from, and
  # `Connection` then initiates an outgoing request, after which it forwards all
  # traffic in both directions.
  #
  # Creating the outgoing request is delegated to a `Proxi::SocketFactory`. The
  # reason being that the type of socket can vary (`TCPSocket`, `SSLSocket`), or
  # there might be some logic involved to dispatch to the correct host, e.g.
  # based on the HTTP Host header (cfr. `Proxi::HTTPHostSocketFactory`).
  #
  # A socket factory can subscribe to events to make informed decision, e.g. to
  # inspect incoming data for HTTP headers.
  #
  # Proxi::Connection broadcasts the following events:
  #
  # - `start_connection(Proxi::Connection)`
  # - `end_connection(Proxi::Connection)`
  # - `main_loop_error(Proxi::Connection, Exception)`
  # - `data_in(Proxi::Connection, Array)`
  # - `data_out(Proxi::Connection, Array)`
  class Connection
    include Wisper::Publisher

    attr_reader :in_socket, :thread

    def initialize(in_socket, socket_factory, max_block_size: 4096)
      @in_socket = in_socket
      @socket_factory = socket_factory
      @max_block_size = max_block_size
    end

    # `Connection#call` starts the connection handler thread. This is called by
    # the server, and spawns a new Thread that handles the forwarding of data.
    def call
      broadcast(:start_connection, self)
      @thread = Thread.new { proxy_loop }
      self
    end

    def alive?
      thread.alive?
    end

    def join_thread
      thread.join
    end

    private

    def out_socket
      @out_socket ||= @socket_factory.call
    end

    def proxy_loop
      begin
        handle_socket(in_socket)
        loop do
          begin
            ready_sockets.each do |socket|
              handle_socket(socket)
            end
          rescue EOFError
            break
          end
        end
      rescue Object => e
        broadcast(:main_loop_error, self, e)
        raise
      ensure
        in_socket.close rescue StandardError
        out_socket.close rescue StandardError
        broadcast(:end_connection, self)
      end
    end

    def ready_sockets
      IO.select([in_socket, out_socket]).first
    end

    def handle_socket(socket)
      data = socket.readpartial(@max_block_size)

      if socket == in_socket
        broadcast(:data_in, self, data)
        out_socket.write data
        out_socket.flush
      else
        broadcast(:data_out, self, data)
        in_socket.write data
        in_socket.flush
      end
    end
  end

end
