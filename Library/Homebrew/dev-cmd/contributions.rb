# typed: true
# frozen_string_literal: true

require "cli/parser"

module Homebrew
  extend T::Sig

  module_function

  SUPPORTED_REPOS = %w[brew core cask bundle].freeze

  sig { returns(CLI::Parser) }
  def contributions_args
    Homebrew::CLI::Parser.new do
      usage_banner <<~EOS
        `contributions [email]`

        Contributions to Homebrew repos for a user.
      EOS

      flag "--from=",
           description: "Date (ISO-8601 format) to start searching contributions."

      flag "--to=",
           description: "Date (ISO-8601 format) to stop searching contributions."

      comma_array "--repos=",
                  description: "The Homebrew repositories to search for contributions in. " \
                               "Comma separated. Supported repos: #{SUPPORTED_REPOS.join(", ")}."

      named_args :email, number: 1
    end
  end

  sig { returns(NilClass) }
  def contributions
    args = contributions_args.parse

    return ofail "`--repos` is required." if args[:repos].empty?

    commits = 0
    coauthorships = 0

    args[:repos].each do |repo|
      if SUPPORTED_REPOS.exclude?(repo)
        return ofail "Unsupported repo: #{repo}. Try one of #{SUPPORTED_REPOS.join(", ")}."
      end

      repo_path = find_repo_path_for_repo(repo)
      return ofail "Couldn't find repo #{repo} locally. Run `brew tap homebrew/#{repo}`." unless repo_path.exist?

      commits += git_log_author_cmd(T.must(repo_path), args)
      coauthorships += git_log_coauthor_cmd(T.must(repo_path), args)
    end

    sentence = "Person #{args.named.first} directly authored #{commits} commits"
    sentence += " and co-authored #{coauthorships} commits"
    sentence += " to #{args[:repos].join(", ")}"
    sentence += if args[:from] && args[:to]
      " between #{args[:from]} and #{args[:to]}"
    elsif args[:from]
      " after #{args[:from]}"
    elsif args[:to]
      " before #{args[:to]}"
    else
      " in all time"
    end
    sentence += "."

    puts sentence
  end

  sig { params(repo: String).returns(Pathname) }
  def find_repo_path_for_repo(repo)
    return HOMEBREW_REPOSITORY if repo == "brew"

    Tap.fetch("homebrew", repo).path
  end

  sig { params(repo_path: Pathname, args: Homebrew::CLI::Args).returns(Integer) }
  def git_log_author_cmd(repo_path, args)
    cmd = "git -C #{repo_path} log --oneline --author=#{args.named.first}"
    cmd += " --before=#{args[:to]}" if args[:to]
    cmd += " --after=#{args[:from]}" if args[:from]

    `#{cmd} | wc -l`.strip.to_i
  end

  sig { params(repo_path: Pathname, args: Homebrew::CLI::Args).returns(Integer) }
  def git_log_coauthor_cmd(repo_path, args)
    cmd = "git -C #{repo_path} log --oneline"
    cmd += " --format='%(trailers:key=Co-authored-by:)'"
    cmd += " --before=#{args[:to]}" if args[:to]
    cmd += " --after=#{args[:from]}" if args[:from]
    cmd += " | grep #{args.named.first}"

    `#{cmd} | wc -l`.strip.to_i
  end
end
