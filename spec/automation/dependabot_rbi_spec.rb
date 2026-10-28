# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../script/dependabot_rbi"

RSpec.describe DependabotRbi do
  let(:directory) { Dir.mktmpdir("dependabot-rbi") }
  let(:repository) { "owner/project" }
  let(:sha) { "a" * 40 }
  let(:api) { instance_double(DependabotRbi::Github) }
  let(:path) { "sorbet/rbi/gems/example@1.0.rbi" }
  let(:content) { "# typed: true\nmodule Example; end\n" }
  let(:artifact) { File.join(directory, "artifact.json") }
  let(:plan_path) { File.join(directory, "plan.json") }
  let(:payload) do
    { "version" => 1, "repository" => repository, "pull_request" => 7, "head_sha" => sha,
      "files" => [ { "path" => path, "content" => content } ] }
  end
  let(:pr) do
    { "state" => "open", "user" => { "login" => "dependabot[bot]" }, "changed_files" => 1,
      "head" => { "sha" => sha, "ref" => "dependabot/bundler/example-1.0", "repo" => { "full_name" => repository } },
      "base" => { "ref" => "main", "repo" => { "full_name" => repository } } }
  end
  let(:event) do
    { "repository" => { "default_branch" => "main" },
      "workflow_run" => { "event" => "pull_request", "conclusion" => "success", "head_sha" => sha,
                          "path" => ".github/workflows/dependabot-rbi.yml", "actor" => { "login" => "dependabot[bot]" },
                          "head_repository" => { "full_name" => repository }, "pull_requests" => [ { "number" => 7 } ] } }
  end

  before do
    File.write(artifact, JSON.generate(payload))
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7").and_return(pr)
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7/files?per_page=100&page=1")
      .and_return([ { "filename" => "Gemfile.lock" } ])
  end

  after { FileUtils.remove_entry(directory) }

  def prepare
    described_class.prepare(event: event, artifact: artifact, output: plan_path, repository: repository, api: api)
  end

  def plan
    payload.merge("head_ref" => pr.fetch("head").fetch("ref"))
  end

  it "prepares only a matching same-repository Dependabot update" do
    expect(prepare).to be(true)
    expect(JSON.parse(File.read(plan_path))).to eq(plan)
  end

  it "produces an explicit no-op for unchanged interfaces" do
    payload["files"] = []
    File.write(artifact, JSON.generate(payload))
    expect(prepare).to be(false)
    expect(JSON.parse(File.read(plan_path)).fetch("files")).to eq([])
  end

  it "rejects unsuccessful, unrelated, or foreign generation runs" do
    changes = { "event" => "push", "conclusion" => "failure", "path" => ".github/workflows/evil.yml",
                "actor" => { "login" => "someone" }, "head_repository" => { "full_name" => "fork/project" } }
    changes.each do |key, value|
      original = event["workflow_run"][key]
      event["workflow_run"][key] = value
      expect { prepare }.to raise_error(described_class::Error, /workflow origin/)
      event["workflow_run"][key] = original
    end
    expect(File).not_to exist(plan_path)
  end

  it "rejects forged artifact identity and unrelated PR numbers" do
    changes = { "version" => 2, "repository" => "other/project", "head_sha" => "b" * 40,
                "pull_request" => 8 }
    changes.each do |key, value|
      forged = payload.merge(key => value)
      File.write(artifact, JSON.generate(forged))
      expect { prepare }.to raise_error(described_class::Error)
    end
    payload["head_sha"] = "not-a-sha"
    event["workflow_run"]["head_sha"] = "not-a-sha"
    File.write(artifact, JSON.generate(payload))
    expect { prepare }.to raise_error(described_class::Error, /identity mismatch/)
  end

  it "rejects closed PRs, forks, changed heads, and non-Bundler branches" do
    original = JSON.generate(pr)
    changes = [
      -> { pr["state"] = "closed" },
      -> { pr["user"]["login"] = "someone" },
      -> { pr["head"]["repo"]["full_name"] = "fork/project" },
      -> { pr["base"]["repo"]["full_name"] = "other/project" },
      -> { pr["head"]["ref"] = "dependabot/github_actions/checkout-7" },
      -> { pr["head"]["ref"] = "dependabot/bundler/../../main" },
      -> { pr["head"]["sha"] = "b" * 40 }
    ]
    changes.each do |change|
      change.call
      expect { prepare }.to raise_error(described_class::Error)
      pr.replace(JSON.parse(original))
    end
  end

  it "rejects nondefault targets and excessively large PRs" do
    pr["base"]["ref"] = "release"
    expect { prepare }.to raise_error(described_class::Error, /default target/)
    pr["base"]["ref"] = "main"
    pr["changed_files"] = 1001
    expect { prepare }.to raise_error(described_class::Error, /file limit/)
  end

  it "checks every page and both sides of renames for executable PR changes" do
    first = Array.new(100) { { "filename" => "Gemfile.lock" } }
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7/files?per_page=100&page=1").and_return(first)
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7/files?per_page=100&page=2")
      .and_return([ { "filename" => path, "previous_filename" => ".github/workflows/ci.yml" } ])
    expect { prepare }.to raise_error(described_class::Error, /source files/)
  end

  it "accepts existing generated RBI changes alongside the lockfile" do
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7/files?per_page=100&page=1")
      .and_return([ { "filename" => path }, { "filename" => "Gemfile" } ])
    expect(prepare).to be(true)
  end

  it "rejects executable, shim, annotation, traversal, and malformed artifact paths" do
    paths = [ "Gemfile", ".github/workflows/ci.yml", "sorbet/rbi/shims/a.rbi", "sorbet/rbi/annotations/a.rbi",
             "sorbet/rbi/gems/../a.rbi", "sorbet/rbi/dsl/./a.rbi", "/sorbet/rbi/gems/a.rbi", "sorbet/rbi/gems/a.rb", nil ]
    paths.each do |invalid|
      expect { described_class.validate_files([ { "path" => invalid, "content" => content } ]) }
        .to raise_error(described_class::Error, /paths/)
    end
  end

  it "rejects invalid file lists, entries, duplicate paths, and content" do
    bad = [ nil, [ {} ], [ 1 ], [ { "path" => path, "content" => content, "extra" => true } ], payload["files"] * 2 ]
    bad.each { |files| expect { described_class.validate_files(files) }.to raise_error(described_class::Error) }
    [ 42, "# typed: true\0bad", "not an RBI", "\xFF".force_encoding("UTF-8") ].each do |invalid|
      expect { described_class.validate_files([ { "path" => path, "content" => invalid } ]) }
        .to raise_error(described_class::Error, /content/)
    end
    stub_const("DependabotRbi::MAX_FILES", 0)
    expect { described_class.validate_files(payload["files"]) }.to raise_error(described_class::Error, /file list/)
  end

  it "bounds individual contents and permits deletions" do
    expect(described_class.validate_files([ { "path" => path, "content" => nil } ])).to eq([ { "path" => path, "content" => nil } ])
    stub_const("DependabotRbi::MAX_FILE_BYTES", 4)
    expect { described_class.validate_files(payload["files"]) }.to raise_error(described_class::Error, /content/)
  end

  it "rejects symlink and oversized JSON artifacts" do
    symlink = File.join(directory, "link.json")
    File.symlink(artifact, symlink)
    expect { described_class.read_json(symlink) }.to raise_error(described_class::Error, /regular JSON/)
    stub_const("DependabotRbi::MAX_BYTES", 4)
    expect { described_class.read_json(artifact) }.to raise_error(described_class::Error, /regular JSON/)
  end

  it "publishes base64 additions and deletions atomically against the expected head" do
    candidate = plan
    candidate["files"] << { "path" => "sorbet/rbi/gems/old@0.9.rbi", "content" => nil }
    response = { "data" => { "createCommitOnBranch" => { "commit" => { "url" => "https://github.com/owner/project/commit/new" } } } }
    allow(api).to receive(:call).with("POST", "graphql", anything).and_return(response)
    result = described_class.publish(plan: candidate, repository: repository, api: api)
    expect(result).to end_with("/commit/new")
    expect(api).to have_received(:call).with("POST", "graphql", hash_including(variables: { input: {
      branch:          { repositoryNameWithOwner: repository, branchName: pr["head"]["ref"] },
      expectedHeadOid: sha,
      message:        { headline: "chore: refresh Dependabot RBI files" },
      fileChanges:    { additions: [ { path: path, contents: Base64.strict_encode64(content) } ],
                        deletions: [ { path: "sorbet/rbi/gems/old@0.9.rbi" } ] }
    } }))
  end

  it "refuses altered plans, empty publication, or a PR that has advanced" do
    expect { described_class.publish(plan: plan, repository: "other/project", api: api) }
      .to raise_error(described_class::Error, /repository mismatch/)
    expect { described_class.publish(plan: plan.merge("files" => []), repository: repository, api: api) }
      .to raise_error(described_class::Error, /Nothing/)
    expect { described_class.publish(plan: plan.merge("pull_request" => "7"), repository: repository, api: api) }
      .to raise_error(described_class::Error, /number/)
    expect { described_class.publish(plan: plan.merge("head_ref" => "other"), repository: repository, api: api) }
      .to raise_error(described_class::Error, /branch mismatch/)
    pr["head"]["sha"] = "b" * 40
    expect { described_class.publish(plan: plan, repository: repository, api: api) }
      .to raise_error(described_class::Error, /head changed/)
  end

  it "collects additions, modifications, and deletions from a real Git working tree" do
    Dir.chdir(directory) do
      described_class.git("init", "-q")
      FileUtils.mkdir_p("sorbet/rbi/gems")
      File.write(path, content)
      File.write("sorbet/rbi/gems/deleted.rbi", content)
      described_class.git("add", ".")
      described_class.git("-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
      File.write(path, content + "module Updated; end\n")
      FileUtils.rm("sorbet/rbi/gems/deleted.rbi")
      File.write("sorbet/rbi/gems/new.rbi", content)
      described_class.collect(repository: repository, number: "7", output: artifact)
      files = JSON.parse(File.read(artifact)).fetch("files")
      expect(files.map { |file| file["path"] }).to contain_exactly(path, "sorbet/rbi/gems/new.rbi", "sorbet/rbi/gems/deleted.rbi")
      expect(files.find { |file| file["path"].include?("deleted") }.fetch("content")).to be_nil
    end
  end

  it "rejects unexpected generated paths, symlinks, oversized bundles, and failed git commands" do
    allow(described_class).to receive(:git).and_return("bad.rb\0")
    expect { described_class.collect(repository: repository, number: 7, output: artifact) }.to raise_error(described_class::Error, /path/)
    Dir.chdir(directory) do
      FileUtils.mkdir_p("sorbet/rbi/gems")
      File.symlink(artifact, path)
      allow(described_class).to receive(:git).and_return("#{path}\0")
      expect { described_class.collect(repository: repository, number: 7, output: artifact) }.to raise_error(described_class::Error, /regular/)
    end
    allow(described_class).to receive(:git).and_return("")
    stub_const("DependabotRbi::MAX_BYTES", 4)
    expect { described_class.collect(repository: repository, number: 7, output: artifact) }.to raise_error(described_class::Error, /too large/)
    allow(described_class).to receive(:git).and_call_original
    expect { described_class.git("not-a-command") }.to raise_error(described_class::Error, /Git command failed/)
  end

  it "routes CLI operations and records explicit changed outputs" do
    env = { "GITHUB_REPOSITORY" => repository, "PR_NUMBER" => "7", "GITHUB_EVENT_PATH" => artifact,
            "GITHUB_OUTPUT" => File.join(directory, "outputs") }
    allow(described_class).to receive(:collect)
    expect(described_class.run([ "collect", artifact ], env)).to eq(0)
    allow(described_class).to receive_messages(prepare: true, publish: "published")
    expect(described_class.run([ "prepare", artifact, plan_path ], env)).to eq(0)
    expect(File.read(env["GITHUB_OUTPUT"])).to eq("changed=true\n")
    expect { expect(described_class.run([ "publish", artifact ], env)).to eq(0) }.to output("published\n").to_stdout
  end

  it "reports CLI validation and JSON errors without publishing" do
    env = { "GITHUB_REPOSITORY" => repository }
    expect { expect(described_class.run([ "unknown" ], env)).to eq(1) }.to output(/Expected collect/).to_stderr
    expect { expect(described_class.run([ "collect" ], env)).to eq(1) }.to output(/PR_NUMBER/).to_stderr
    expect { expect(described_class.run([], env.merge("GITHUB_REPOSITORY" => "../bad"))).to eq(1) }.to output(/Invalid repository/).to_stderr
    File.write(artifact, "bad json")
    expect { expect(described_class.run([ "publish", artifact ], env)).to eq(1) }.to output(/unexpected|parse|invalid/i).to_stderr
  end
end
