require 'socket'
require 'thread'
require 'openssl'
require 'zlib'
require 'stringio'

require 'wisper'

# [Proxi](https://github.com/plexus/proxi) gives you flexible TCP/HTTP proxy
# servers for use during development.
#
# This can be useful when developing against external services, to see what goes
# over the wire, capture responses, or simulate timeouts.
#
# There are three main concepts in Proxi, `Server`, `Connection`, and `Socket`.
# A server listens locally for incoming requests. When it receives a request, it
# establishes a `Connection`, which opens a socket to the remote host, and then
# acts as a bidirectional pipe between the incoming and outgoing network
# sockets.
#
# To allow for multiple ways to handle the proxying, and multiple strategies for
# making remote connections, the `Server` does not create `Connections`
# directly, but instead delegates this to a "connection factory".
#
# A `Connection` in turn delegates how to open a remote socket to a "socket
# factory".
#
# Both Servers and Connections are observable, they emit events that objects can
# subscribe to.
#
# To use Proxi, hook up these factories, and register event listeners, and then
# start the server.
module Proxi

  # ## Basic examples
  #
  # These are provided for basic use cases, and as a starting point for more
  # complex uses. They return the server instance, call `#call` to start the
  # server, or use `on` or `subscribe` to listen to events.

  # With `Proxy.tcp_proxy` you get basic proxying from a local port to a remote
  # host and port, all bytes are simply forwarded without caring about their
  # contents.
  #
  # For example:
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

  # `Proxi.http_host_proxy` allows proxying to multiple remote hosts, based on
  # the HTTP `Host:` header. To use it, gather the IP addresses that correspond
  # to each domain name, and provide this name-to-ip mapping to
  # `http_host_proxy`. Now configure these domain names in `/etc/hosts` to point
  # to the local host, so Proxi can intercept traffic intended for these
  # domains.
  #
  # For example
  #
  #     Proxi.http_host_proxy(80, {'foo.example.org' => '10.10.0.1'}).call
  def self.http_host_proxy(local_port, host_mapping)
    reporter = ConsoleReporter.new

    connection_factory = -> in_socket do
      socket_factory = HTTPHostSocketFactory.new(host_mapping)
      Connection
        .new(in_socket, socket_factory)
        .subscribe(socket_factory, on: :data_in)
        #.subscribe(reporter)
    end

    Server.new(local_port, connection_factory)
  end
end

require_relative 'proxi/server'
require_relative 'proxi/connection'
require_relative 'proxi/socket_factory'
require_relative 'proxi/reporting'
require_relative 'proxi/listeners'
require_relative 'proxi/http'
