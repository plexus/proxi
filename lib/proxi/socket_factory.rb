module Proxi
  # Public: Create outgoing TCP sockets
  #
  # Suitable when all requests need to be forwarded to the same host and port.
  class TCPSocketFactory
    def initialize(remote_host, remote_port)
      @remote_host, @remote_port = remote_host, remote_port
    end

    def call
      TCPSocket.new(@remote_host, @remote_port)
    end
  end

  # Public: Create outgoing SSL connections
  #
  # This will set up an encrypted (SSL, https) connection to the target host.
  # This way the proxy server communicates *unencrypted* locally, but
  # encrypts/decrypts communication with the remote host.
  #
  # If you want to forward SSL connections as-is, use a TCPSocketFactory, in
  # that case however you won't be able to inspect any data passing through,
  # since it will be encrypted.
  class SSLSocketFactory < TCPSocketFactory
    def call
      OpenSSL::SSL::SSLSocket.new(super).tap(&:connect)
    end
  end

  # Public: Dispatch HTTP traffic to multiple hosts
  #
  # Forward traffic to a specific host based on the HTTP Host header, and a
  # mapping of hosts to ip addresses.
  #
  # HTTPHostSocketFactory expects to receive data events from the connection, so
  # make sure you subscribe it to connection events.
  #
  # To use this effectively, configure your local /etc/hosts so the relevant
  # domains point to localhost. That way the proxy will be able to intercept
  # them.
  #
  # Single use only! Create a new instance for each Proxi::Connection.
  #
  # Examples
  #
  #    mapping = {'foo.example.com' => '10.10.10.1:8080'}
  #
  #    Proxi::Server.new(
  #      '80',
  #      ->(in_socket) {
  #        socket_factory = HTTPHostSocketFactory.new(mapping)
  #        connection = Proxi::Connection.new(in_socket, socket_factory)
  #        connection.subscribe(socket_factory, on: :data_in)
  #      }
  #    ).call
  class HTTPHostSocketFactory

    # Public: Initialize a HTTPHostSocketFactory
    #
    # host_mapping - A Hash mapping hostnames to IP addresses, and, optionally, ports
    #
    # Examples
    #
    #     HTTPHostSocketFactory.new(
    #       'foo.example.com' => '10.10.10.1:8080',
    #       'bar.example.com' => '10.10.10.2:8080'
    #     )
    def initialize(host_mapping)
      @host_mapping = host_mapping
    end

    # Internal: receive data event from the connection
    def data_in(connection, data)
      @first_packet ||= data
    end

    def call
      host, port = @host_to_ip.fetch(headers["host"]).split(':')
      port ||= 80
      TCPSocket.new(host, port.to_i)
    end

    def headers
      Hash[
        @first_packet
        .sub(/\r\n\r\n.*/m, '')
        .each_line
        .drop(1) # GET / HTTP/1.1
        .map do |line|
          k,v = line.split(':', 2)
          [k.downcase, v.strip]
        end
      ]
    end
  end
end
