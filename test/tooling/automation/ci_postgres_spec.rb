# typed: false

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "fileutils"
require "tmpdir"
require "open3"
require "yaml"

RSpec.describe "CI PostgreSQL bootstrap" do # rubocop:disable RSpec/DescribeClass
  let(:directory) { Dir.mktmpdir("ci-postgres") }

  around do |example|
    executable("docker", <<~BASH)
      printf "docker %s\\n" "$*" >> "$CALLS"
      if [[ "$2" == version ]]; then exit "${PLUGIN_STATUS:-0}"; fi
      if [[ "$*" == *"logs --tail"* ]]; then echo "PostgreSQL startup diagnostic"; fi
      exit "${DOCKER_STATUS:-0}"
    BASH
    executable("docker-compose", <<~BASH)
      printf "docker-compose %s\\n" "$*" >> "$CALLS"
      if [[ "$*" == *"logs --tail"* ]]; then echo "PostgreSQL startup diagnostic"; fi
      exit "${DOCKER_STATUS:-0}"
    BASH
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

  it "uses the development Compose model with only CI port and restart overrides" do
    _stdout, _stderr, status = bootstrap

    expect(status).to be_success
    expect(calls).to include("--project-name guileful-charger-ci -f .devcontainer/compose.yaml -f .github/ci/postgres.compose.yml up -d --build --no-deps postgres")
    override = YAML.load_file(File.expand_path("../../../.github/ci/postgres.compose.yml", __dir__))
    expect(override).to eq("services" => { "postgres" => { "restart" => "no", "ports" => [ "5432:5432" ] } })
    expect(calls.scan("probe").size).to eq(1)
  end

  it "supports standalone Compose when the Docker plugin is unavailable" do
    _stdout, _stderr, status = bootstrap("PLUGIN_STATUS" => "1")

    expect(status).to be_success
    expect(calls).to include("docker-compose --project-name guileful-charger-ci", "up -d --build --no-deps postgres")
  end

  it "fails after bounded readiness attempts" do
    _stdout, stderr, status = bootstrap("READY_STATUS" => "1")

    expect(status).not_to be_success
    expect(calls.scan("probe").size).to eq(60)
    expect(calls.scan("down --volumes --remove-orphans").size).to eq(2)
    expect(stderr).to include("PostgreSQL startup diagnostic")
    expect(calls.index("logs --tail 200")).to be < calls.rindex("down --volumes")
  end

  it "replaces only its dedicated CI project when run repeatedly" do
    2.times { expect(bootstrap.last).to be_success }

    expect(calls.scan("down --volumes --remove-orphans").size).to eq(2)
    expect(calls.scan("up -d --build --no-deps postgres").size).to eq(2)
    expect(calls.lines.grep(/down|up/)).to all(include("--project-name guileful-charger-ci"))
  end

  it "stops when Docker fails" do
    _stdout, _stderr, status = bootstrap("DOCKER_STATUS" => "1")

    expect(status).not_to be_success
    expect(calls).not_to include("probe", "up -d")
  end
end
