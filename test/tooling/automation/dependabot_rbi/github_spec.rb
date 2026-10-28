# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require_relative "../../../../script/dependabot_rbi"

RSpec.describe DependabotRbi::Github do
  it "passes JSON over stdin without shell interpolation and accepts arrays" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return([ "{}", "", status ], [ "[]", "", status ])
    client = described_class.new
    expect(client.call("POST", "graphql", { value: "$(unsafe)" })).to eq({})
    expect(client.call("GET", "repos/owner/project/pulls/7/files")).to eq([])
    expect(Open3).to have_received(:capture3).with("gh", "api", "--method", "POST", "graphql", "--input", "-", stdin_data: '{"value":"$(unsafe)"}')
  end

  it "rejects HTTP and GraphQL errors" do
    success = instance_double(Process::Status, success?: true)
    failure = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return([ "", "private detail", failure ], [ '{"errors":[{"type":"FORBIDDEN"}]}', "", success ])
    expect { described_class.new.call("GET", "repos/owner/project") }.to raise_error(DependabotRbi::Error, /request failed/)
    expect { described_class.new.call("POST", "graphql", {}) }.to raise_error(DependabotRbi::RequestError, /rejected.*FORBIDDEN/)
  end

  it "recognizes concurrent head changes even when gh exits unsuccessfully" do
    failure = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return([ '{"errors":[{"type":"STALE_DATA"}]}', "", failure ])

    expect { described_class.new.call("POST", "graphql", {}) }.to raise_error(DependabotRbi::StaleHead)
  end

  it "preserves structured error codes so the publisher can confirm branch-deletion races" do
    success = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return([ '{"errors":[{"type":"NOT_FOUND"},null,{"type":42}]}', "", success ])

    expect { described_class.new.call("POST", "graphql", {}) }
      .to raise_error(DependabotRbi::RequestError, /NOT_FOUND/) { |error| expect(error.codes).to eq([ "NOT_FOUND" ]) }
  end

  it "bounds logged error codes and excludes response messages or malformed types" do
    success = instance_double(Process::Status, success?: true)
    codes = Array.new(12) { |index| "CODE_#{index}" }
    errors = codes.map { |code| { "type" => code, "message" => "sensitive response" } }
    errors += [ { "type" => "unsafe\nresponse" }, { "type" => "X" * 65 }, { "type" => "CODE_0" } ]
    allow(Open3).to receive(:capture3).and_return([ JSON.generate("errors" => errors), "", success ])

    expect { described_class.new.call("POST", "graphql", {}) }.to raise_error(DependabotRbi::RequestError) do |error|
      expect(error.codes).to eq(codes)
      expect(error.message).to eq("GitHub rejected the request [#{codes.first(10).join(', ')}]")
      expect(error.message).not_to include("sensitive response", "unsafe", "CODE_10")
    end
  end

  it "preserves failed HTTP and proxy diagnostics even when the body is not JSON" do
    failure = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return([ "<html>502 Bad Gateway</html>", "gh: HTTP 502 (proxy unavailable)", failure ])

    expect { described_class.new.call("GET", "repos/owner/project") }
      .to raise_error(DependabotRbi::Error, /request failed: GET repos\/owner\/project: gh: HTTP 502 \(proxy unavailable\)/)
  end

  it "reports invalid successful JSON without dumping the response contents" do
    success = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return([ "sensitive response", "", success ])

    expect { described_class.new.call("GET", "repos/owner/project") }
      .to raise_error(DependabotRbi::Error, "GitHub returned invalid JSON: GET repos/owner/project")
  end

  it "rejects malformed GraphQL error containers and entries with friendly diagnostics" do
    success = instance_double(Process::Status, success?: true)
    [ { "type" => "STALE_DATA" }, [ "bad entry" ] ].each do |errors|
      allow(Open3).to receive(:capture3).and_return([ JSON.generate("errors" => errors), "", success ])

      expect { described_class.new.call("POST", "graphql", {}) }
        .to raise_error(DependabotRbi::RequestError, "GitHub rejected the request")
    end
  end

  it "retains HTTP diagnostics before validating an unsuccessful response's error shape" do
    failure = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return([ '{"errors":["invalid field"]}', "gh: Validation failed (HTTP 422)", failure ])

    expect { described_class.new.call("POST", "graphql", {}) }
      .to raise_error(DependabotRbi::Error, /Validation failed \(HTTP 422\)/)
  end
end
