require 'proxi'

class EventCollector
  def initialize
    @collected_events = []
  end

  def method_missing(*args)
    @collected_events << args
  end

  def respond_to?(*)
    true
  end

  def events
    @collected_events
  end
end

RSpec.describe Proxi::HTTPMessage do
  specify 'content-length' do
    rest = subject.append("GET /foo HTTP/1.1\r\nHost: foo.bar\r\nContent-length: 20\r\n\r\nbody,more body,even more body")
    expect(rest).to eql "more body"
    expect(subject.body).to eql "body,more body,even "
    expect(subject.headers).to eql("host" => "foo.bar", "content-length" => "20")
  end

  specify 'chunked' do
    rest = subject.append("GET /foo HTTP/1.1\r\nHost: foo.bar\r\nTransfer-encoding: chunked\r\n\r\n5\r\nbody,\r\n18\r\nmore body,even more body\r\n\r\nnext message")
    #expect(rest).to eql "next message"
    expect(subject.body).to eql "body,more body,even more body"
    expect(subject.headers).to eql("host" => "foo.bar", "transfer-encoding" => "chunked")
  end
end

RSpec.describe Proxi::HTTPRequestSplitter do
  let(:event_collector) { EventCollector.new }

  specify do
    subject.subscribe(event_collector)

    subject.data_in(nil, "GET /foo HTTP/1.1\r\nHost: foo.bar\r\n\r\n")
    subject.data_in(nil, "GET /bar HTTP/1.1\r\nHost: foo.bar\r\n\r\n")

    subject.data_out(nil, "HTTP/1.1 200 OK\r\nTransfer-encoding: chunked\r\n\r\n5\r\nabcde\r\n5\r\n12345\r\n\r\nHTTP/1.1 200 OK\r\nContent-length: 10\r\n\r\n12345abcde trailing garbage")

    expect(event_collector.events.length).to eql 2
    expect(event_collector.events.map(&:first)).to eql [:http_request, :http_request]

    _, req1, res1 = event_collector.events.first
    _, req2, res2 = event_collector.events.last

    expect(req1.head_line).to eql "GET /foo HTTP/1.1\r\n"
    expect(req2.head_line).to eql "GET /bar HTTP/1.1\r\n"
    expect(res1.body).to eql "abcde12345"
    expect(res2.body).to eql "12345abcde"
  end

end
