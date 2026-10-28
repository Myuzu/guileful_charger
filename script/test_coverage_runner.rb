# frozen_string_literal: true

require "coverage"
require "rspec/core"

module TestCoverageRunner
  ROOT = File.expand_path("..", __dir__)
  PROFILES = {
    "automation" => {
      specs: %w[test/tooling/automation],
      files: %w[script/dependabot_rbi.rb script/test_coverage_runner.rb bin/test_tooling config/boot.rb lib/dry_type_catalog.rb]
    },
    "compiler" => {
      specs: %w[test/tooling/tapioca/dsl/compilers/dry_type_namespaces_spec.rb],
      files: %w[sorbet/tapioca/compilers/dry_type_namespaces.rb]
    }
  }.freeze

  def self.run(args, owns_coverage: false, coverage: Coverage, runner: RSpec::Core::Runner, output: $stdout)
    profile = PROFILES.fetch(args.fetch(0))
    status = Dir.chdir(ROOT) { runner.run(profile.fetch(:specs)) }
    results = owns_coverage ? coverage.result : coverage.peek_result
    complete = profile.fetch(:files).map do |path|
      lines = begin
        expanded = File.expand_path(path, ROOT)
        entry = results[File.realpath(expanded)] || results[expanded]
        entry.is_a?(Hash) ? entry[:lines] : entry
      rescue SystemCallError
        nil
      end
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
