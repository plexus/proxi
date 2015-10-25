# ### Reporting
#
# Proxi's server and connection classes don't have any logging or UI
# capabilities built in, but they broadcast events that we can listen to to perform these tasks.

module Proxi
  # This is a very basic console reporter to see what's happening
  #
  # Subscribe to connection events, and you will see output that looks like this
  #
  #     1. +++
  #     1. < 91
  #     2. +++
  #     3. +++
  #     2. < 91
  #     3. < 91
  #     1. > 4096
  #     1. > 3422
  #     1. ---
  #
  # Each connection gets a unique incremental number assigned, followed by:
  #
  # - '+++' new connection
  # - '---' connection closed
  # - '< 1234' number of bytes proxied to the remote
  # - '> 1234' number of bytes proxied back from the remote
  class ConsoleReporter
    def initialize
      @count = 0
      @mutex = Mutex.new
      @connections = {}
    end

    def start_connection(conn)
      @mutex.synchronize { @connections[conn] = (@count += 1) }
      puts "#{@connections[conn]}. +++"
    end

    def end_connection(conn)
      puts "#{@connections[conn]}. ---"
      @connections.delete(conn)
    end

    def data_in(conn, data)
      puts "#{@connections[conn]}. < #{data.size}"
    end

    def data_out(conn, data)
      puts "#{@connections[conn]}. > #{data.size}"
    end

    def main_loop_error(conn, exc)
      STDERR.puts "#{@connections[conn]}. #{exc.class} #{exc.message}"
      STDERR.puts exc.backtrace
    end
  end
end
