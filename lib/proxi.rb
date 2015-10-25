require 'socket'
require 'thread'
require 'optparse'
require 'tmpdir'
require 'openssl'

require 'wisper'

module Proxi
  def self.tcp_proxy(local_port, remote_host, remote_port)
    reporter = ConsoleReporter.new

    Server.new(
      local_port,
      -> in_socket do
        Connection.new(
          in_socket,
          TCPSocketFactory.new(remote_host, remote_port)
        ).subscribe(reporter)
      end
    )
  end

  def self.http_host_proxy(local_port, host_mapping)
    reporter = ConsoleReporter.new

    Server.new(
      local_port,
      -> in_socket do
        socket_factory = HTTPHostSocketFactory.new(host_mapping)
        Connection
          .new(in_socket, socket_factory)
          .subscribe(socket_factory, on: :data_in)
          .subscribe(reporter)
      end
    )
  end
end

require_relative 'proxi/server'
require_relative 'proxi/connection'
require_relative 'proxi/socket_factory'
require_relative 'proxi/reporting'
