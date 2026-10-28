# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "fileutils"
require "tmpdir"
require "open3"

RSpec.describe "CI PostgreSQL bootstrap" do # rubocop:disable RSpec/DescribeClass
  let(:directory) { Dir.mktmpdir("ci-postgres") }

  around do |example|
    executable("docker", 'printf "%s\n" "$*" >> "$CALLS"; exit "${DOCKER_STATUS:-0}"')
    executable("pg_isready", 'printf "probe\n" >> "$CALLS"; exit "${READY_STATUS:-0}"')
    executable("sleep", ":")
    example.run
  ensure
    FileUtils.remove_entry(directory)
  end

  def executable(name, body)
    path = File.join(directory, name)
    File.write(path, "#!/bin/bash\n#{body}\n")
    File.chmod(0o755, path)
  end

  def bootstrap(extra = {})
    env = { "PATH" => "#{directory}:/usr/bin:/bin", "CALLS" => File.join(directory, "calls") }.merge(extra)
    Open3.capture3(env, "/bin/bash", File.expand_path("../../../script/ci_postgres.sh", __dir__))
  end

  def calls
    File.read(File.join(directory, "calls"))
  end

  it "uses the same development database and pg_cron configuration for both workflows" do
    _stdout, _stderr, status = bootstrap

    expect(status).to be_success
    expect(calls).to include("POSTGRES_DB=guileful_charger_development", "shared_preload_libraries=pg_cron",
      "cron.database_name=guileful_charger_development", "build -f .devcontainer/postgres/Dockerfile")
    expect(calls.scan("probe").size).to eq(1)
  end

  it "fails after bounded readiness attempts" do
    _stdout, _stderr, status = bootstrap("READY_STATUS" => "1")

    expect(status).not_to be_success
    expect(calls.scan("probe").size).to eq(60)
  end

  it "stops when Docker fails" do
    _stdout, _stderr, status = bootstrap("DOCKER_STATUS" => "1")

    expect(status).not_to be_success
    expect(calls).not_to include("probe", "run -d")
  end
end
