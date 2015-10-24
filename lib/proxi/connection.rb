module Proxi
  class Connection
    include Wisper::Publisher

    attr_reader :in_socket, :thread, :remote_host, :remote_port

    def initialize(in_socket, remote_host, remote_port)
      @in_socket = in_socket
      @remote_host, @remote_port = remote_host, remote_port
      @state = :new
    end

    def call
      broadcast(:start_connection, self)
      @thread = Thread.new { proxy_loop }
    end

    def alive?
      thread.alive?
    end

    def join_thread
      thread.join
    end

    private

    def out_socket
      @out_socket ||= TCPSocket.new(remote_host, remote_port)
    end

    def proxy_loop
      begin
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
      data = socket.readpartial(4096)

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

  module SSLConnection
    def connect
      @out_socket = OpenSSL::SSL::SSLSocket.new(super)
      @out_socket.connect
    end
  end

  class HTTPConnection < Connection
    def initialize(in_socket, host_to_ip)
      @in_socket, @host_to_ip = in_socket, host_to_ip
      @new = true
    end

    def handle_socket(socket)
      data = socket.readpartial(4096)

      if socket == in_socket
        broadcast(:data_in, self, data)

        if @new
          @first_packet = data
          @new = false
        end

        out_socket.write data
        out_socket.flush
      else
        broadcast(:data_out, self, data)
        in_socket.write data
        in_socket.flush
      end
    end

    def ready_sockets
      if @new
        sockets = [in_socket]
      else
        sockets = [in_socket, out_socket]
      end
      IO.select(sockets).first
    end

    def out_socket
      host, port = @host_to_ip.fetch(headers["host"]).split(':')
      port ||= 80
      @out_socket ||= TCPSocket.new(host, port.to_i)
    end

    def headers
      Hash[
        @first_packet
        .sub(/\r\n\r\n.*/m, '')
        .each_line
        .drop(1) # GET / HTTP/1.1
        .map do |line|
          k,v = line.split(':', 2)
          [k.downcase, v.strip].tap do |header|
            broadcast(:header, self, *header)
          end
        end
      ]
    end
  end
end
