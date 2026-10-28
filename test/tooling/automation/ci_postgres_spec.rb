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
      if [[ "$1 $2" == "container inspect" ]]; then exit "${LEGACY_STATUS:-1}"; fi
      if [[ "$1 $2" == "container rm" ]]; then exit "${LEGACY_REMOVE_STATUS:-0}"; fi
      if [[ "$*" == *"logs --tail"* ]]; then echo "PostgreSQL startup diagnostic"; fi
      exit "${DOCKER_STATUS:-0}"
    BASH
    executable("docker-compose", <<~BASH)
      printf "docker-compose %s\\n" "$*" >> "$CALLS"
      if [[ "$1" == version ]]; then
        echo "${STANDALONE_VERSION:-5.6.1}"
        exit "${STANDALONE_STATUS:-0}"
      fi
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

  it "loads only the shared database model with CI port and restart overrides" do
    _stdout, _stderr, status = bootstrap

    expect(status).to be_success
    expect(calls).to include("--project-name guileful-charger-ci -f .devcontainer/postgres/compose.yaml -f .github/ci/postgres.compose.yml up -d --build --no-deps postgres")
    expect(calls).not_to include("-f .devcontainer/compose.yaml", "container rm")
    override = YAML.load_file(File.expand_path("../../../.github/ci/postgres.compose.yml", __dir__))
    expect(override).to eq("services" => { "postgres" => { "restart" => "no", "ports" => [ "5432:5432" ] } })
    expect(calls.scan("probe").size).to eq(1)
  end

  it "shares the effective database, build, volume and cron settings with development" do
    root = File.expand_path("../../..", __dir__)
    shared = YAML.load_file(File.join(root, ".devcontainer/postgres/compose.yaml"))
    service = shared.fetch("services").fetch("postgres")
    development = YAML.load_file(File.join(root, ".devcontainer/compose.yaml")).fetch("services").fetch("postgres")

    expect(shared.fetch("services").keys).to eq([ "postgres" ])
    expect(service.fetch("environment")).to eq("POSTGRES_DB" => "guileful_charger_development", "POSTGRES_USER" => "postgres", "POSTGRES_PASSWORD" => "postgres")
    expect(service.fetch("command")).to eq([ "postgres", "-c", "shared_preload_libraries=pg_cron", "-c", "cron.database_name=guileful_charger_development" ])
    expect(service.fetch("build")).to eq("context" => "../..", "dockerfile" => ".devcontainer/postgres/Dockerfile")
    expect(service.fetch("volumes")).to eq([ "postgres-data:/var/lib/postgresql" ])
    expect(shared.fetch("volumes").keys).to eq([ "postgres-data" ])
    expect(development).to eq("extends" => { "file" => "postgres/compose.yaml", "service" => "postgres" }, "restart" => "unless-stopped")
  end

  it "supports current standalone Compose releases when the Docker plugin is unavailable" do
    %w[2.40.0 v5.6.1].each do |version|
      _stdout, _stderr, status = bootstrap("PLUGIN_STATUS" => "1", "STANDALONE_VERSION" => version)

      expect(status).to be_success
    end
    expect(calls).to include("docker-compose --project-name guileful-charger-ci", "up -d --build --no-deps postgres")
  end

  it "rejects legacy, unavailable or unrecognized standalone versions before changing containers" do
    [ { "STANDALONE_VERSION" => "1.29.2" }, { "STANDALONE_VERSION" => "unknown" }, { "STANDALONE_STATUS" => "1" } ].each do |settings|
      _stdout, stderr, status = bootstrap(settings.merge("PLUGIN_STATUS" => "1"))

      expect(status).not_to be_success
      expect(stderr).to include("Docker Compose 2 or later is required")
    end
    expect(calls).not_to include("container inspect", "container rm", "down --volumes", "up -d", "probe")
  end

  it "removes the exact legacy CI container before starting the isolated project" do
    _stdout, _stderr, status = bootstrap("LEGACY_STATUS" => "0")

    expect(status).to be_success
    expect(calls.lines.grep(/container rm/)).to eq([ "docker container rm --force --volumes guileful-charger-ci-postgres\n" ])
    expect(calls.index("container rm")).to be < calls.index("down --volumes")
    expect(calls.index("container rm")).to be < calls.index("up -d")
  end

  it "stops and reports diagnostics if the legacy CI container cannot be removed" do
    _stdout, stderr, status = bootstrap("LEGACY_STATUS" => "0", "LEGACY_REMOVE_STATUS" => "1")

    expect(status).not_to be_success
    expect(stderr).to include("PostgreSQL startup diagnostic")
    expect(calls).not_to include("probe", "up -d")
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
