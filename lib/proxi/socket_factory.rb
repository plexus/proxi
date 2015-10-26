# ## Socket factories
#
module Proxi
  # ### TCPSocketFactory
  #
  # This is the most vanilla type of socket factory.
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

  # ### SSLSocketFactory
  #
  # This will set up an encrypted (SSL, https) connection to the target host.
  # This way the proxy server communicates *unencrypted* locally, but
  # encrypts/decrypts communication with the remote host.
  #
  # If you want to forward SSL connections as-is, use a `TCPSocketFactory`, in
  # that case however you won't be able to inspect any data passing through,
  # since it will be encrypted.
  class SSLSocketFactory < TCPSocketFactory
    def call
      OpenSSL::SSL::SSLSocket.new(super).tap(&:connect)
    end
  end

  # ### HTTPHostSocketFactory
  #
  # Dispatches HTTP traffic to multiple hosts, based on the HTTP `Host:` header.
  #
  # HTTPHostSocketFactory expects to receive data events from the connection, so
  # make sure you subscribe it to connection events. (see `Proxi.http_proxy` for
  # an example).
  #
  # To use this effectively, configure your local `/etc/hosts` so the relevant
  # domains point to localhost. That way the proxy will be able to intercept
  # them.
  #
  # This class is single use only! Create a new instance for each `Proxi::Connection`.
  class HTTPHostSocketFactory

    # Initialize a HTTPHostSocketFactory
    #
    # `host_mapping` - A Hash mapping hostnames to IP addresses, and, optionally, ports
    #
    # For example:
    #
    #     HTTPHostSocketFactory.new(
    #       'foo.example.com' => '10.10.10.1:8080',
    #       'bar.example.com' => '10.10.10.2:8080'
    #     )
    def initialize(host_mapping)
      @host_mapping = host_mapping
    end

    # This is an event listener, it will be broadcast by the `Connection` whenever
    # it gets new request data. We capture the first packet, assuming it
    # contains the HTTP headers.
    #
    # `Connection` will only request an outgoing socket from us (call `#call`)
    # after it received the initial request payload.
    def data_in(connection, data)
      @first_packet ||= data
    end

    def call
      host, port = @host_mapping.fetch(headers["host"]).split(':')
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
