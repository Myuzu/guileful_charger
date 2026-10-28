# frozen_string_literal: true

require "coverage"
require "rspec/core"

module TestCoverageRunner
  PROFILES = {
    "automation" => {
      specs: %w[test/tooling/automation],
      files: %w[script/dependabot_rbi.rb script/test_coverage_runner.rb bin/test_tooling]
    },
    "runtime" => {
      specs: %w[test/tooling/runtime],
      files: %w[config/initializers/sorbet.rb lib/sorbet_runtime_policy.rb]
    },
    "compiler" => {
      specs: %w[test/tooling/tapioca/dsl/compilers/dry_type_namespaces_spec.rb],
      files: %w[sorbet/tapioca/compilers/dry_type_namespaces.rb]
    }
  }.freeze

  def self.run(args, coverage: Coverage, runner: RSpec::Core::Runner, output: $stdout)
    profile = PROFILES.fetch(args.fetch(0))
    status = runner.run(profile.fetch(:specs))
    results = coverage.result
    complete = profile.fetch(:files).map do |path|
      lines = results.dig(File.realpath(path), :lines)
      if lines.nil? || lines.compact.empty?
        output.puts "No executable coverage for #{path}"
        false
      else
        missed = lines.each_index.select { |index| lines[index] == 0 }.map { |index| index + 1 }
        output.puts missed.empty? ? "#{path}: 100% line coverage" : "Uncovered lines in #{path}: #{missed.join(', ')}"
        missed.empty?
      end
    end.all?
    complete ? status : 1
  rescue IndexError => error
    output.puts "Select a coverage profile: #{PROFILES.keys.join(', ')} (#{error.message})"
    1
  end
end
