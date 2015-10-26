module Proxi

  # ## Listening for HTTP requests
  #
  # The events that `Connection` broadcasts are very low level, you get
  # `data_in` and `data_out` for every packet that comes and goes. When dealing
  # with HTTP requests that isn't very convenient. You might have multiple
  # requests coming over the same connection, some using gzip or chunked
  # transfer encoding, how do you get to the pure request data?
  #
  # `HTTPRequestSplitter` to the rescue! You subscribe it to events on a
  # `Connection`, and in turn it will output a single event, `http_request`,
  # with two arguments: a `HTTPRequestMessage` and a `HTTPResponseMessage`.
  #
  # Now you can get at the `headers` or `body` without having to care about
  # those low level details
  #
  class HTTPRequestSplitter
    include Wisper::Publisher

    attr_reader :requests, :response

    def initialize
      @requests = [HTTPRequestMessage.new]
      @response = HTTPResponseMessage.new
    end

    def data_in(conn, data)
      request = @requests.last
      rest = request.append(data)
      if request.done?
        request = HTTPRequestMessage.new
        @requests << request
        data_in(conn, rest) if rest
      end
    end

    def data_out(conn, data)
      rest = @response.append(data)
      if @response.done?
        request = @requests.shift
        broadcast(:http_request, request, @response)
        @response = HTTPResponseMessage.new
        data_out(conn, rest) if rest
      end
    end
  end

  class HTTPMessage
    CRLF = "\r\n"
    attr_reader :head

    def initialize
      @head = ""
      @body = ""
      @chunk_length = nil
      @current_chunk = ""
      @done = false
    end

    def append(data)
      if @head.end_with? CRLF+CRLF
        if chunked?
          append_chunks(data)
        else
          append_by_content_length(data)
        end
      else
        h, b = data.split(/(?<=#{CRLF}#{CRLF})/, 2)
        @head << h
        append(b) if b
      end
    end

    def append_chunks(data)
      if @chunk_length.nil?
        if data.start_with?(CRLF)
          data = data.sub(CRLF, '')
          @done = true
          data unless data.empty?
        else
          @chunk_length = data.hex
          @chunk_length = nil if @chunk_length == 0
          data = data.each_line.drop(1).join
          append_chunks(data)
        end
      else
        part = data.bytes.take(remaining_bytes).pack('C*')
        rest = data.bytes.drop(remaining_bytes).pack('C*')
        @current_chunk << part
        if remaining_bytes == 0
          @body << @current_chunk
          @chunk_length = nil
          @current_chunk = ""
          rest = rest.sub(CRLF, '')
          append_chunks(rest) unless rest.empty?
        end
      end
    end

    def append_by_content_length(data)
      part = data.bytes.take(remaining_bytes)
      rest = data.bytes.drop(remaining_bytes)
      @body << part.pack('C*')
      @done = remaining_bytes == 0
      rest.pack('C*') if rest.any?
    end

    def content_length
      headers["content-length"].to_i
    end

    def chunked?
      headers["transfer-encoding"] == 'chunked'
    end

    def remaining_bytes
      if chunked?
        @chunk_length - @current_chunk.length
      else
        content_length - body.length
      end
    end

    def head_line
      head.each_line.first
    end

    def headers
      Hash[
        head.each_line.drop(1).map(&:chomp).reject(&:empty?).map do |line|
          k,v = line.split(':', 2)
          [k.downcase, v.strip]
        end
      ]
    end

    def body
      if headers['content-encoding'] =~ /gzip/
        Zlib::GzipReader.new(StringIO.new(@body)).read
      else
        @body
      end
    end

    def done?
      @done
    end
  end

  class HTTPRequestMessage < HTTPMessage
    def http_method
      head_line.split(' ')[0]
    end

    def path
      head_line.split(' ')[1]
    end
  end

  class HTTPResponseMessage < HTTPMessage
    def status_code
      head_line.split(' ')[1]
    end

    def status_text
      head_line.split(' ')[2]
    end
  end

  # An example
  -> {
    # Set up a basic proxy server.
    server = Proxi.tcp_proxy('8080', '127.0.0.1', '9090')

    server.on(:new_connection) { |conn|
      # We need a splitter for each connection, because it tracks connection
      # state.
      http_splitter = Proxi::HTTPRequestSplitter.new

      # Hook it up to listen to data coming in.
      conn.subscribe(http_splitter)

      # Handle HTTP requests however you see fit.
      http_splitter.on(:http_request) do |req, res|
        puts "#{req.http_method} #{req.path} => #{res.status_code} #{res.status_text}"
      end
    }

    # Now we're ready to boot up the server!
    server.call
  }
end
