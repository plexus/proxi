#!/usr/bin/ruby

require 'socket'
require 'thread'
require 'optparse'
require 'tmpdir'

class ProxyServer
  attr_reader :switches
  attr_reader :listen_port, :remote_host, :remote_port
  attr_reader :mutex
  attr_accessor :threads

  def initialize(listen_port, remote_host, remote_port, switches = [])
    @listen_port, @remote_host, @remote_port = listen_port, remote_host, remote_port
    @server = TCPServer.new(nil, @listen_port)
    @switches = switches

    @threads = []
    @max_threads = 5
    @count = 0
    @mutex = Mutex.new

    @count += 1 while File.exist? log_name(@count, :in)
  end

  def start
    loop do
      # begin
      threads << Thread.new(@server.accept) do |in_socket|
        handle_new_thread(in_socket)
      end
      # rescue Interrupt => e
      #   STDERR << e.message
      # end

      threads.select {|t| not t.alive? }.each do |dead|
          dead[:logfd].values {|f| f.close} if dead[:logfd]
      end

      self.threads = threads.select { |t| t.alive? ? true : (t.join; false) }
      while threads.size >= @max_threads
        sleep 1
        self.threads = threads.select { |t| t.alive? ? true : (t.join; false) }
      end
    end
  end

  def handle_new_thread(in_socket)
    @mutex.synchronize { Thread.current[:count] = @count+=1 }
    begin

      begin
        out_socket = TCPSocket.new(remote_host, remote_port)
        if switches[:s]
          puts "OPENSSL"
          require 'openssl'
          out_socket = OpenSSL::SSL::SSLSocket.new( out_socket )
          out_socket.connect
        end
      rescue Errno::ECONNREFUSED
        in_socket.close
        raise
      end

      proxy_data(in_socket, out_socket)

    rescue StandardError => e
      puts "Thread #{Thread.current} got exception #{e.inspect}"
    end

    in_socket.close rescue StandardError
    out_socket.close rescue StandardError
  end

  def proxy_data(in_socket, out_socket)
    loop do
      (ready_sockets, dummy, dummy) = IO.select([in_socket, out_socket])
      begin
        if switches[:wait]
          sleep switches[:wait]
        end
        ready_sockets.each do |socket|
          data = socket.readpartial(4096)
          if socket == in_socket
            if switches[:vhost]
              vhost = remote_port.to_i == 80 ? switches[:vhost] : "#{switches[:vhost]}:#{remote_port}"
              data.gsub!(/^Host: [^\r]+/, "Host: #{vhost}")
            end
            log(:in, data)
            out_socket.write data
            out_socket.flush
          else
            log(:out, data)
            in_socket.write data
            in_socket.flush
          end
        end
      rescue EOFError
        break
      end
    end
  end

  def name
    switches[:name] || 'proxy'
  end

  def dirname
    switches[:dir] || Dir.tmpdir
  end

  def log_name(num, suffix)
    '%s/%s.%d.%d.%s' % [dirname, name, listen_port, num, suffix]
  end

  def log(in_out, str)
    if switches[:m] || switches[:mm]
      if in_out == :in
        printf "Thread # %d : input %d bytes\n" % [Thread.current[:count], str.size]
        Thread.current[:starttime] ||= Time.now
      else
        if Thread.current[:gotdata]
          if switches[:mm]
            printf "Thread # %d : continued %.2fs , %d bytes\n" % [Thread.current[:count], Time.now - Thread.current[:starttime], str.size]
          end
        else
          Thread.current[:gotdata] = true
          printf "Thread # %d : reply started %.2fs , %d bytes\n" % [Thread.current[:count], Time.now - Thread.current[:starttime], str.size]
        end
      end
    end
    if switches[:l]
      unless Thread.current[:logfd]
        num = Thread.current[:count]
        Thread.current[:logfd] = {
          :in => File.open(log_name(num, :in), 'w'),
          :out => File.open(log_name(num, :out), 'w')
        }
      end
      Thread.current[:logfd][in_out] << str
      Thread.current[:logfd][in_out].flush
    end
  end
end



switches = {}

optparse = OptionParser.new do |opts|
  opts.banner = "#{File.basename($0)} [options] <src port> <host> <dst port>"
  opts.on('-w', '--wait SECONDS', 'wait after accepting the connection')                                    { |sec| switches[:wait] = Integer( sec ) }
  opts.on('-l', '--log'         , 'log to /tmp')                                                            { switches[:l]  = true }
  opts.on('-v', '--vhost HOST'  , 'rewrite HTTP "Host:" header, useful when the server uses virtual hosts') { |host| switches[:vhost] = host }
  opts.on('-n', '--name NAME'   , 'specify an alternative prefix for the log files (default "proxy")')      { |name| switches[:name] = name }
  opts.on('-m', '--timing'      , 'print time and size information to stdout')                              { switches[:m]  = true }
  opts.on('-x', '--xtiming'     , 'give more elaborate timing information on stdout')                       { switches[:mm] = true }
  opts.on('-s', '--ssl'         , 'connect to HTTPS, i.e. do SSL socket termination"')                      { switches[:s]  = true }
  opts.on('-d', '--dir DIR'     , 'Directory to place the logs, defaults to the temp dir')                  { |dir| switches[:dir] = dir }
  opts.on('-o', '--hostmap ip:vhost,ip:vhost', 'provide a mapper from ip to hostname')                      { |m| switches[:hostmap] = Hash[m.split(',').map{|o| o.split(':').reverse}] }
  opts.on('-h', '--help'        , 'Print this help message')                                                { puts opts ; exit}
end

optparse.parse! ARGV

p ARGV

unless ARGV.count == 3
  puts optparse
  exit
end

p switches

listen_port, remote_host, remote_port = *ARGV

ProxyServer.new(listen_port, remote_host, remote_port, switches).start
