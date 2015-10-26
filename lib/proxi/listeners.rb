# ## Server Listeners
#
# These can be attached to a server to add extra behavior
#
module Proxi

  # Log all incoming and outgoing traffic to files under `/tmp`
  #
  # For example:
  #
  #      Proxi.tcp_server(...).subscribe(RequestResponseLogging.new).call
  #
  # The in and outgoing traffic will be captured per connection in
  # `/tmp/proxi.1.in` and `/tmp/proxi.1.out`; `/tmp/proxi.2.in`, etc.
  class RequestResponseLogging
    def initialize(dir: Dir.tmpdir, name: "proxi")
      @dir = dir
      @name = name
      @count = 0
      @mutex = Mutex.new
    end

    def new_connection(connection)
      count = @mutex.synchronize { @count += 1 }
      in_fd = File.open(log_name(count, "in"), 'w')
      out_fd = File.open(log_name(count, "out"), 'w')

      connection
        .on(:data_in) { |_, data| in_fd.write(data) ; in_fd.flush }
        .on(:data_out) { |_, data| out_fd.write(data) ; out_fd.flush }
        .on(:end_connection) { in_fd.close ; out_fd.close }
    end

    def log_name(num, suffix)
      '%s/%s.%d.%s' % [@dir, @name, num, suffix]
    end
  end

  # Wait before handing back data coming from the remote, this simulates a slow
  # connection, and can be used to test timeouts.
  class SlowDown
    def initialize(wait_seconds: 5)
      @wait_seconds = wait_seconds
    end

    def new_connection(connection)
      connection.on(:data_out) { sleep @wait_seconds }
    end
  end

end
