require 'socket'
require 'thread'
require 'openssl'

require 'wisper'

# Proxi gives you flexible TCP/HTTP proxy servers for use during development.
module Proxi

  # With `Proxy.tcp_proxy` you get basic proxying from a local port to a remote
  # host and port, all bytes are simply forwarded without caring about their
  # contents.
  #
  #     Proxi.tcp_proxy(3000, 'foo.example.com', 4000).call
  def self.tcp_proxy(local_port, remote_host, remote_port)
    reporter = ConsoleReporter.new

    connection_factory = -> in_socket do
      socket_factory = TCPSocketFactory.new(remote_host, remote_port)
      Connection.new(in_socket, socket_factory).subscribe(reporter)
    end

    Server.new(local_port, connection_factory)
  end

  # Public: A proxy with HTTP Host dispatching
  #
  # Examples
  #
  #    Proxi.http_host_proxy(80, {'foo.example.org' => '10.10.0.1'}).call
  def self.http_host_proxy(local_port, host_mapping)
    reporter = ConsoleReporter.new

    connection_factory = -> in_socket do
      socket_factory = HTTPHostSocketFactory.new(host_mapping)
      Connection
        .new(in_socket, socket_factory)
        .subscribe(socket_factory, on: :data_in)
        .subscribe(reporter)
    end

    Server.new(local_port, connection_factory)
  end
end

require_relative 'proxi/server'
require_relative 'proxi/connection'
require_relative 'proxi/socket_factory'
require_relative 'proxi/reporting'
