# frozen_string_literal: true

require "json"
require "open3"

# The publisher runs this file from the default branch, without installing gems
# or executing PR code. Artifact contents are data used only in a GitHub commit.
module DependabotRbi
  class Error < StandardError; end
  class StaleHead < Error; end
  class RequestError < Error
    attr_reader :codes

    def initialize(message, codes: [])
      super(message)
      @codes = codes
    end
  end

  MAX_FILES = 1000
  MAX_BYTES = 64 * 1024 * 1024
  MAX_FILE_BYTES = 4 * 1024 * 1024
  SHA_PATTERN = /\A[0-9a-f]{40}\z/
  PATH_PATTERN = %r{\Asorbet/rbi/(?:gems|dsl)/(?:[A-Za-z0-9_@.+-]+/)*[A-Za-z0-9_@.+-]+\.rbi\z}
  COMMIT_QUERY = <<~GRAPHQL
    mutation($input: CreateCommitOnBranchInput!) {
      createCommitOnBranch(input: $input) { commit { url } }
    }
  GRAPHQL

  class Github
    def call(method, path, body = nil)
      args = [ "gh", "api", "--method", method, path ]
      args.concat([ "--input", "-" ]) if body
      stdout, stderr, status = Open3.capture3(*args, stdin_data: body ? JSON.generate(body) : "")
      failure = "GitHub request failed: #{method} #{path}: #{stderr.strip[0, 2000]}"
      result = begin
        stdout.empty? ? {} : JSON.parse(stdout)
      rescue JSON::ParserError
        DependabotRbi.check(status.success?, failure)
        raise Error, "GitHub returned invalid JSON: #{method} #{path}"
      end
      if !status.success? || (result.is_a?(Hash) && result.key?("errors"))
        errors = result.is_a?(Hash) ? result["errors"] : nil
        codes = errors.is_a?(Array) ? errors.filter_map { |error| error["type"] if error.is_a?(Hash) }.grep(String) : []
        raise StaleHead, "PR head advanced during publication" if codes.include?("STALE_DATA")

        message = status.success? ? "GitHub rejected the request" : failure
        raise RequestError.new(message, codes: codes)
      end
      result
    end
  end

  def self.check(condition, message)
    raise Error, message unless condition
  end

  def self.rbi_path?(path)
    path.is_a?(String) && PATH_PATTERN.match?(path) && path.split("/").none? { |part| part == "." || part == ".." }
  end

  def self.read_json(path)
    check(File.lstat(path).file? && File.size(path) <= MAX_BYTES, "Expected a regular JSON file smaller than 64 MiB")
    result = JSON.parse(File.read(path, encoding: "UTF-8"))
    check(result.is_a?(Hash), "Expected a JSON object")
    result
  end

  def self.validate_files(files)
    check(files.is_a?(Array) && files.size <= MAX_FILES, "Invalid RBI file list")
    paths = files.map do |file|
      check(file.is_a?(Hash) && file.keys.sort == %w[content path], "Invalid RBI entry")
      check(rbi_path?(file["path"]), "Only generated gem and DSL RBI paths are allowed")
      content = file["content"]
      check(content.nil? || (content.is_a?(String) && content.valid_encoding? && !content.include?("\0") &&
        content.bytesize <= MAX_FILE_BYTES && content.start_with?("# typed:")), "Invalid RBI content")
      file["path"]
    end
    check(paths.uniq.size == paths.size, "Duplicate RBI paths")
    files
  end

  def self.git(*args)
    environment = ENV.keys.grep(/\AGIT_/).to_h { |name| [ name, nil ] }
    stdout, _stderr, status = Open3.capture3(environment, "git", *args)
    check(status.success?, "Git command failed")
    stdout
  end

  def self.collect(repository:, number:, output:)
    paths = %w[sorbet/rbi/gems sorbet/rbi/dsl]
    changed = git("diff", "--name-only", "-z", "HEAD", "--", *paths).split("\0")
    added = git("ls-files", "--others", "--exclude-standard", "-z", "--", *paths).split("\0")
    files = (changed + added).uniq.sort.grep(/\.rbi\z/).map do |path|
      check(rbi_path?(path), "Unexpected generated path")
      check(!File.symlink?(path) && (!File.exist?(path) || File.file?(path)), "Generated RBIs must be regular files")
      { "path" => path, "content" => File.exist?(path) ? File.read(path, encoding: "UTF-8") : nil }
    end
    validate_files(files)
    payload = { "version" => 1, "repository" => repository, "pull_request" => Integer(number),
                "head_sha" => git("rev-parse", "HEAD").strip, "files" => files }
    encoded = JSON.generate(payload)
    check(encoded.bytesize <= MAX_BYTES, "RBI artifact is too large")
    File.write(output, encoded)
  end

  def self.validate_pr(pr, repository:, sha:)
    check(pr.dig("user", "login") == "dependabot[bot]", "Expected a Dependabot PR")
    raise StaleHead, "PR is closed or merged; nothing to publish" if pr["state"] == "closed"

    check(pr["state"] == "open", "Expected an open Dependabot PR")
    check(pr.dig("head", "repo", "full_name") == repository && pr.dig("base", "repo", "full_name") == repository,
      "Fork PRs are not eligible")
    branch = pr.dig("head", "ref")
    check(branch.is_a?(String) && branch.start_with?("dependabot/bundler/") &&
      %r{\A[A-Za-z0-9_./-]+\z}.match?(branch) && !branch.include?(".."), "Expected a Bundler Dependabot branch")
    raise StaleHead, "PR head changed; wait for regeneration on the new commit" unless pr.dig("head", "sha") == sha
  end

  def self.gem_arguments(previous_lock, current_lock)
    # Reserve full regeneration of same-version interfaces for changes to the
    # generator, runtime signatures, or reflection tools.
    pattern = /^    (?:tapioca|rbi|rubydex|spoom|sorbet|sorbet-runtime|sorbet-static) \(.+\)$/
    previous_lock.lines.grep(pattern) == current_lock.lines.grep(pattern) ? [] : [ "--all" ]
  end

  def self.prepare(event:, artifact:, output:, repository:, api: Github.new)
    run = event.fetch("workflow_run")
    check(run["event"] == "pull_request" && run["conclusion"] == "success" &&
      run["path"] == ".github/workflows/dependabot-rbi.yml" && run.dig("actor", "login") == "dependabot[bot]" &&
      run.dig("head_repository", "full_name") == repository, "Unexpected generation workflow origin")
    payload = read_json(artifact)
    check(payload["version"] == 1 && payload["repository"] == repository &&
      payload["head_sha"] == run["head_sha"] && SHA_PATTERN.match?(payload["head_sha"].to_s), "Artifact identity mismatch")
    number = payload["pull_request"]
    check(number.is_a?(Integer) && number.positive?, "Invalid artifact PR number")
    associations = run.fetch("pull_requests")
    check(associations.is_a?(Array) && associations.all? { |pr| pr.is_a?(Hash) }, "Invalid workflow PR associations")
    associated = associations.any? { |pr| pr["number"] == number }
    check(associations.empty? || associated,
      "Artifact does not belong to this workflow's PR")
    pr = api.call("GET", "repos/#{repository}/pulls/#{number}")
    validate_pr(pr, repository: repository, sha: payload["head_sha"])
    check(associated, "Artifact does not belong to this workflow's current PR")
    check(pr.dig("base", "ref") == event.dig("repository", "default_branch"), "Expected the default target branch")
    check(pr.fetch("changed_files") <= MAX_FILES, "PR exceeds the file limit")
    page = 1
    listed = 0
    loop do
      files = api.call("GET", "repos/#{repository}/pulls/#{number}/files?per_page=100&page=#{page}")
      listed += files.size
      check(listed <= MAX_FILES, "PR file listing exceeds the limit")
      files.each do |file|
        names = [ file.fetch("filename"), file["previous_filename"] ].compact
        check(names.all? { |name| %w[Gemfile Gemfile.lock].include?(name) || rbi_path?(name) }, "PR changes non-dependency source files")
      end
      break if files.size < 100

      page += 1
    end
    check(listed == pr.fetch("changed_files"), "Incomplete or changed PR file listing")
    plan = payload.merge("head_ref" => pr.fetch("head").fetch("ref"), "files" => validate_files(payload.fetch("files")))
    File.write(output, JSON.generate(plan))
    !plan["files"].empty?
  end

  def self.publish(plan:, repository:, api: Github.new)
    check(plan["repository"] == repository, "Publication repository mismatch")
    files = validate_files(plan.fetch("files"))
    check(!files.empty?, "Nothing to publish")
    number = plan.fetch("pull_request")
    check(number.is_a?(Integer) && number.positive?, "Invalid pull request number")
    pr = api.call("GET", "repos/#{repository}/pulls/#{number}")
    validate_pr(pr, repository: repository, sha: plan.fetch("head_sha"))
    check(pr.dig("head", "ref") == plan["head_ref"], "Publication branch mismatch")
    additions = files.reject { |file| file["content"].nil? }.map do |file|
      { path: file["path"], contents: [ file["content"] ].pack("m0") }
    end
    deletions = files.select { |file| file["content"].nil? }.map { |file| { path: file["path"] } }
    input = { branch:          { repositoryNameWithOwner: repository, branchName: plan.fetch("head_ref") },
              expectedHeadOid: plan.fetch("head_sha"),
              message:        { headline: "chore: refresh Dependabot RBI files [dependabot skip]" },
              fileChanges:    { additions: additions, deletions: deletions } }
    result = api.call("POST", "graphql", { query: COMMIT_QUERY, variables: { input: input } })
    url = result.fetch("data").fetch("createCommitOnBranch").fetch("commit").fetch("url")
    current = api.call("GET", "repos/#{repository}/pulls/#{number}")
    if current["state"] == "closed"
      raise StaleHead, "PR closed while publication was in flight; commit #{url} was created and may remain on the closed branch"
    end
    url
  rescue RequestError => error
    raise unless error.codes.include?("NOT_FOUND")

    current = api.call("GET", "repos/#{repository}/pulls/#{number}")
    validate_pr(current, repository: repository, sha: plan.fetch("head_sha"))
    raise error
  end

  def self.run(args, env = ENV)
    begin
      repository = env.fetch("GITHUB_REPOSITORY")
      check(%r{\A[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+\z}.match?(repository) &&
        !%w[. ..].include?(repository.split("/").last), "Invalid repository")
      case args.fetch(0)
      when "gem-arguments"
        base = args.fetch(1)
        check(SHA_PATTERN.match?(base), "Invalid base SHA")
        merge_base = git("merge-base", base, "HEAD").strip
        puts gem_arguments(git("show", "#{merge_base}:Gemfile.lock"), File.read("Gemfile.lock"))
      when "collect"
        collect(repository: repository, number: env.fetch("PR_NUMBER"), output: args.fetch(1))
      when "prepare"
        changed = prepare(event: read_json(env.fetch("GITHUB_EVENT_PATH")), artifact: args.fetch(1), output: args.fetch(2), repository: repository)
        File.open(env.fetch("GITHUB_OUTPUT"), "a") { |file| file.puts("changed=#{changed}") }
      when "publish"
        puts publish(plan: read_json(args.fetch(1)), repository: repository)
      else
        raise Error, "Expected gem-arguments, collect, prepare, or publish"
      end
    rescue StaleHead => error
      puts "Skipping outdated generation: #{error.message}"
      if args.first == "prepare"
        File.open(env.fetch("GITHUB_OUTPUT"), "a") { |file| file.puts("changed=false") }
      end
    end
    0
  rescue Error, IndexError, JSON::ParserError, ArgumentError, TypeError, SystemCallError => error
    warn error.message
    1
  end
end

exit DependabotRbi.run(ARGV) if $PROGRAM_NAME == __FILE__
