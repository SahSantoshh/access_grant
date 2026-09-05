# frozen_string_literal: true

require_relative "lib/access_grant/version"

Gem::Specification.new do |spec|
  spec.name = "access_grant"
  spec.version = AccessGrant::VERSION
  spec.authors = ["SahSantoshh"]
  spec.email = ["sahsantoshh@gmail.com"]
  spec.summary = "Dynamic, database-backed, per-tenant role and permission management for Rails."
  spec.description = <<~DESC
    AccessGrant gives Rails apps a role-based access control system where permissions
    live in the database and can be reassigned to roles by tenant admins at runtime,
    with no deploy required. Unlike Pundit/CanCanCan/Action Policy (which hardcode
    permission logic in Ruby policy/ability classes) or Rolify (which manages role
    assignment but has no concept of permissions), AccessGrant ships a code-defined
    permission catalog synced into the database, dynamic per-tenant roles, and a
    permitted?(key) check.
  DESC
  spec.homepage = "https://github.com/santoshsah/access_grant"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github .idea .junie])
    end
  end
  spec.require_paths = ["lib"]
end
