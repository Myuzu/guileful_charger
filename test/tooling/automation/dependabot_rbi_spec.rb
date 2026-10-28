# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../../script/dependabot_rbi"

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

  it "skips closed or merged Dependabot PRs before preparing or publishing" do
    pr["state"] = "closed"
    [ false, true ].each do |merged|
      pr["merged"] = merged
      expect { prepare }.to raise_error(described_class::StaleHead, /closed or merged/)
      expect { described_class.publish(plan: plan, repository: repository, api: api) }
        .to raise_error(described_class::StaleHead, /closed or merged/)
    end
    expect(File).not_to exist(plan_path)
    expect(api).not_to have_received(:call).with("POST", "graphql", anything)
  end

  it "skips closed and superseded PRs even when GitHub omits their run associations" do
    event["workflow_run"]["pull_requests"] = []
    pr["state"] = "closed"
    expect { prepare }.to raise_error(described_class::StaleHead, /closed/)
    pr["state"] = "open"
    pr["head"]["sha"] = "b" * 40
    expect { prepare }.to raise_error(described_class::StaleHead, /head changed/)
    expect(File).not_to exist(plan_path)
  end

  it "replays real GitHub empty-association data through the complete CLI preflight" do
    recorded = JSON.parse(File.read(File.expand_path("../fixtures/closed_dependabot_run.json", __dir__)))
    identity = { "repository" => recorded.fetch("repository"), "head_sha" => recorded.fetch("head_sha"), "pull_request" => recorded.dig("pr", "number") }
    File.write(artifact, JSON.generate(payload.merge(identity)))
    run = event.fetch("workflow_run").merge("head_sha" => identity["head_sha"], "pull_requests" => recorded["pull_requests"],
      "head_repository" => { "full_name" => identity["repository"] })
    event_path = File.join(directory, "event.json")
    File.write(event_path, JSON.generate(event.merge("workflow_run" => run)))
    allow(described_class::Github).to receive(:new).and_return(api)
    allow(api).to receive(:call).with("GET", "repos/#{identity['repository']}/pulls/#{identity['pull_request']}").and_return(recorded.fetch("pr"))
    env = { "GITHUB_REPOSITORY" => identity["repository"], "GITHUB_EVENT_PATH" => event_path,
            "GITHUB_OUTPUT" => File.join(directory, "outputs") }

    expect { expect(described_class.run([ "prepare", artifact, plan_path ], env)).to eq(0) }.to output(/Skipping outdated generation: PR is closed/).to_stdout
    expect(File.read(env["GITHUB_OUTPUT"])).to eq("changed=false\n")
    expect(File).not_to exist(plan_path)
  end

  it "rejects a current head with no association or a malformed association list" do
    [ [], {} ].each do |associations|
      event["workflow_run"]["pull_requests"] = associations
      expect { prepare }.to raise_error(described_class::Error, /PR/)
    end
    payload["pull_request"] = "7"
    File.write(artifact, JSON.generate(payload))
    expect { prepare }.to raise_error(described_class::Error, /PR number/)
  end

  it "rejects unknown PR states" do
    pr["state"] = "unexpected"

    expect { prepare }.to raise_error(described_class::Error, /open Dependabot/)
  end

  it "selects full reflection only when the generator toolchain changes" do
    before = "    tapioca (0.20.0)\n    rbi (0.3.7)\n    sorbet-runtime (0.6.1)\n    dry-types (1.9.1)\n"
    ordinary = before.sub("1.9.1", "1.9.2")

    expect(described_class.gem_arguments(before, ordinary)).to eq([])
    expect(described_class.gem_arguments(before, before.sub("0.20.0", "0.21.0"))).to eq([ "--all" ])
    expect(described_class.gem_arguments(before, before.sub("0.3.7", "0.3.8"))).to eq([ "--all" ])
    expect(described_class.gem_arguments(before, before.sub("0.6.1", "0.6.2"))).to eq([ "--all" ])
  end

  it "routes generation argument selection through the validated base lockfile" do
    fork = "b" * 40
    allow(described_class).to receive(:git).with("merge-base", sha, "HEAD").and_return("#{fork}\n")
    allow(described_class).to receive(:git).with("show", "#{fork}:Gemfile.lock").and_return("    tapioca (old)\n")
    env = { "GITHUB_REPOSITORY" => repository }

    expect { expect(described_class.run([ "gem-arguments", sha ], env)).to eq(0) }.to output("--all\n").to_stdout
    expect { expect(described_class.run([ "gem-arguments", "--bad" ], env)).to eq(1) }.to output(/Invalid base SHA/).to_stderr
  end

  it "compares against the fork point when main advances independently of a dependency PR" do
    fixture = File.join(directory, "divergent")
    FileUtils.mkdir_p(fixture)
    Dir.chdir(fixture) do
      described_class.git("init", "-q", "-b", "main")
      commit_lock("    tapioca (0.20.0)\n")
      described_class.git("branch", "dependency")
      base_tip = commit_lock("    tapioca (0.21.0)\n")
      described_class.git("checkout", "-q", "dependency")
      commit_lock("    tapioca (0.20.0)\n    dry-types (1.9.2)\n")
      env = { "GITHUB_REPOSITORY" => repository }
      expect { expect(described_class.run([ "gem-arguments", base_tip ], env)).to eq(0) }.not_to output.to_stdout
      commit_lock("    tapioca (0.21.0)\n    dry-types (1.9.2)\n")
      expect { expect(described_class.run([ "gem-arguments", base_tip ], env)).to eq(0) }.to output("--all\n").to_stdout
    end
  end

  def commit_lock(content)
    File.write("Gemfile.lock", content)
    described_class.git("add", "Gemfile.lock")
    described_class.git("-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
    described_class.git("rev-parse", "HEAD").strip
  end

  it "collects RBI files while ignoring generated metadata and other non-RBI files" do
    allow(described_class).to receive(:git).with("diff", anything, any_args).and_return("sorbet/rbi/gems/.gitattributes\0")
    allow(described_class).to receive(:git).with("ls-files", anything, any_args).and_return("sorbet/rbi/dsl/.gitattributes\0sorbet/rbi/dsl/README.md\0")
    allow(described_class).to receive(:git).with("rev-parse", "HEAD").and_return(sha)

    described_class.collect(repository: repository, number: 7, output: artifact)

    expect(JSON.parse(File.read(artifact)).fetch("files")).to eq([])
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
    pr["changed_files"] = 2
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
      message:        { headline: "chore: refresh Dependabot RBI files [dependabot skip]" },
      fileChanges:    { additions: [ { path: path, contents: "IyB0eXBlZDogdHJ1ZQptb2R1bGUgRXhhbXBsZTsgZW5kCg==" } ],
                        deletions: [ { path: "sorbet/rbi/gems/old@0.9.rbi" } ] }
    } }))
  end

  it "skips a branch-deletion race only after confirming that the PR closed or advanced" do
    candidate = plan
    failure = described_class::RequestError.new("Branch no longer exists", codes: [ "NOT_FOUND" ])
    allow(api).to receive(:call).with("POST", "graphql", anything).and_raise(failure)
    closed = pr.merge("state" => "closed", "merged" => true)
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7").and_return(pr, closed)
    expect { described_class.publish(plan: candidate, repository: repository, api: api) }
      .to raise_error(described_class::StaleHead, /closed or merged/)

    advanced = pr.merge("head" => pr.fetch("head").merge("sha" => "b" * 40))
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7").and_return(pr, advanced)
    expect { described_class.publish(plan: candidate, repository: repository, api: api) }
      .to raise_error(described_class::StaleHead, /head changed/)
  end

  it "does not hide a missing-branch error for a current open PR or other request failures" do
    [ [ "NOT_FOUND" ], [ "FORBIDDEN" ] ].each do |codes|
      failure = described_class::RequestError.new("Request failed", codes: codes)
      allow(api).to receive(:call).with("POST", "graphql", anything).and_raise(failure)
      expect { described_class.publish(plan: plan, repository: repository, api: api) }.to raise_error(failure)
    end
  end

  it "preserves the mutation error when its missing-branch recovery read also fails" do
    candidate = plan
    mutation_error = described_class::RequestError.new("Original missing branch", codes: [ "NOT_FOUND" ])
    verification_error = described_class::RequestError.new("Recovery GET failed with HTTP 502")
    allow(api).to receive(:call).with("POST", "graphql", anything).and_raise(mutation_error)
    reads = 0
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7") do
      reads += 1
      raise verification_error if reads > 1

      pr
    end

    expect do
      expect { described_class.publish(plan: candidate, repository: repository, api: api) }.to raise_error(mutation_error)
    end.to output(/Could not confirm PR state.*Recovery GET failed with HTTP 502/).to_stderr
  end

  it "does not apply missing-branch recovery to failed preflight requests" do
    failure = described_class::RequestError.new("Initial PR read failed", codes: [ "NOT_FOUND" ])
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7").and_raise(failure)

    expect { described_class.publish(plan: plan, repository: repository, api: api) }.to raise_error(failure)
    expect(api).to have_received(:call).with("GET", "repos/#{repository}/pulls/7").once
    expect(api).not_to have_received(:call).with("POST", "graphql", anything)
  end

  it "returns a successful commit even when the optional post-publish PR read fails" do
    candidate = plan
    url = "https://github.com/owner/project/commit/new"
    response = { "data" => { "createCommitOnBranch" => { "commit" => { "url" => url } } } }
    allow(api).to receive(:call).with("POST", "graphql", anything).and_return(response)
    failure = described_class::RequestError.new("Post-publish GET failed", codes: [ "NOT_FOUND" ])
    reads = 0
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7") do
      reads += 1
      raise failure if reads > 1

      pr
    end

    expect do
      expect(described_class.publish(plan: candidate, repository: repository, api: api)).to eq(url)
    end.to output("Published #{url}; could not recheck PR state: Post-publish GET failed\n").to_stderr
    expect(reads).to eq(2)
  end

  it "prints the landed commit URL and succeeds when post-publish verification is rate limited" do
    File.write(plan_path, JSON.generate(plan))
    url = "https://github.com/owner/project/commit/new"
    response = { "data" => { "createCommitOnBranch" => { "commit" => { "url" => url } } } }
    allow(api).to receive(:call).with("POST", "graphql", anything).and_return(response)
    allow(described_class::Github).to receive(:new).and_return(api)
    reads = 0
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7") do
      reads += 1
      raise described_class::RequestError, "HTTP 403 rate limit exceeded" if reads > 1

      pr
    end

    expect do
      expect do
        expect(described_class.run([ "publish", plan_path ], "GITHUB_REPOSITORY" => repository)).to eq(0)
      end.to output("#{url}\n").to_stdout
    end.to output(/Published #{Regexp.escape(url)}; could not recheck PR state: HTTP 403/).to_stderr
  end

  it "reports an in-flight close after a successful commit without rewriting branch history" do
    candidate = plan
    closed = pr.merge("state" => "closed", "merged" => true)
    response = { "data" => { "createCommitOnBranch" => { "commit" => { "url" => "https://github.com/owner/project/commit/new" } } } }
    allow(api).to receive(:call).with("POST", "graphql", anything).and_return(response)
    allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7").and_return(pr, closed)

    expect { described_class.publish(plan: candidate, repository: repository, api: api) }
      .to raise_error(described_class::StaleHead, %r{commit https://github.com/owner/project/commit/new was created.*closed branch})
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

  it "ignores inherited Git hook variables when operating on a fixture repository" do
    foreign = File.join(directory, "foreign")
    fixture = File.join(directory, "fixture")
    FileUtils.mkdir_p([ foreign, fixture ])
    Dir.chdir(foreign) { described_class.git("init", "-q") }
    inherited = { "GIT_DIR" => File.join(foreign, ".git"), "GIT_INDEX_FILE" => File.join(foreign, "hook-index") }
    previous = inherited.to_h { |name, _value| [ name, ENV[name] ] }
    ENV.update(inherited)
    Dir.chdir(fixture) do
      described_class.git("init", "-q")
      File.write("fixture.txt", "safe")
      described_class.git("add", "fixture.txt")
      described_class.git("-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
      expect(described_class.git("rev-parse", "--show-toplevel").strip).to eq(File.realpath(fixture))
    end
    expect(File).not_to exist(inherited.fetch("GIT_INDEX_FILE"))
    Dir.chdir(foreign) { expect(described_class.git("log", "--all", "--oneline")).to eq("") }
  ensure
    previous&.each { |name, value| ENV[name] = value }
  end

  it "checks the terminal page at the file limit and rejects overflowing or incomplete listings" do
    pr["changed_files"] = 1000
    page = Array.new(100) { { "filename" => "Gemfile.lock" } }
    (1..10).each do |number|
      allow(api).to receive(:call).with("GET", "repos/#{repository}/pulls/7/files?per_page=100&page=#{number}").and_return(page)
    end
    terminal = "repos/#{repository}/pulls/7/files?per_page=100&page=11"
    allow(api).to receive(:call).with("GET", terminal).and_return([])
    expect(prepare).to be(true)
    expect(api).to have_received(:call).with("GET", terminal)
    allow(api).to receive(:call).with("GET", terminal).and_return([ { "filename" => "Gemfile.lock" } ])
    expect { prepare }.to raise_error(described_class::Error, /listing exceeds/)
    pr["changed_files"] = 999
    allow(api).to receive(:call).with("GET", terminal).and_return([])
    expect { prepare }.to raise_error(described_class::Error, /Incomplete/)
  end

  it "skips stale preparation and publication successfully without minting a changed result" do
    env = { "GITHUB_REPOSITORY" => repository, "GITHUB_EVENT_PATH" => artifact,
            "GITHUB_OUTPUT" => File.join(directory, "outputs") }
    allow(described_class).to receive(:prepare).and_raise(described_class::StaleHead, "new head")
    allow(described_class).to receive(:publish).and_raise(described_class::StaleHead, "new head")
    expect do
      expect(described_class.run([ "prepare", artifact, plan_path ], env)).to eq(0)
      expect(described_class.run([ "publish", artifact ], env)).to eq(0)
    end.to output(/Skipping outdated generation: new head/).to_stdout
    expect(File.read(env["GITHUB_OUTPUT"])).to eq("changed=false\n")
  end

  it "rejects unexpected generated paths, symlinks, oversized bundles, and failed git commands" do
    allow(described_class).to receive(:git).and_return("sorbet/rbi/gems/../bad.rbi\0")
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
    expect { expect(described_class.run([ "unknown" ], env)).to eq(1) }.to output(/Expected gem-arguments/).to_stderr
    expect { expect(described_class.run([ "collect" ], env)).to eq(1) }.to output(/PR_NUMBER/).to_stderr
    expect { expect(described_class.run([], env.merge("GITHUB_REPOSITORY" => "../bad"))).to eq(1) }.to output(/Invalid repository/).to_stderr
    File.write(artifact, "bad json")
    expect { expect(described_class.run([ "publish", artifact ], env)).to eq(1) }.to output(/unexpected|parse|invalid/i).to_stderr
  end

  it "reports missing files, output paths, and non-object JSON without a backtrace" do
    env = { "GITHUB_REPOSITORY" => repository, "GITHUB_EVENT_PATH" => artifact,
            "GITHUB_OUTPUT" => File.join(directory, "missing", "outputs") }
    expect { expect(described_class.run([ "publish", "#{artifact}.missing" ], env)).to eq(1) }.to output(/No such file/).to_stderr
    File.write(artifact, "[]")
    expect { expect(described_class.run([ "publish", artifact ], env)).to eq(1) }.to output(/JSON object/).to_stderr
    File.write(artifact, JSON.generate(payload))
    allow(described_class).to receive(:prepare).and_raise(described_class::StaleHead, "head changed")
    allow(described_class).to receive(:puts)
    expect { expect(described_class.run([ "prepare", artifact, plan_path ], env)).to eq(1) }.to output(/No such file/).to_stderr
  end

  it "reports invalid argument types through the CLI diagnostic boundary" do
    env = { "GITHUB_REPOSITORY" => repository }

    expect { expect(described_class.run([ "gem-arguments", {} ], env)).to eq(1) }.to output(/String/).to_stderr
  end
end
