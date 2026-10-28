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
    expect { described_class.new.call("POST", "graphql", {}) }.to raise_error(DependabotRbi::Error, /branch may have advanced/)
  end

  it "recognizes concurrent head changes even when gh exits unsuccessfully" do
    failure = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return([ '{"errors":[{"type":"STALE_DATA"}]}', "", failure ])

    expect { described_class.new.call("POST", "graphql", {}) }.to raise_error(DependabotRbi::StaleHead)
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
end
