# frozen_string_literal: true

require "active_support/inflector"
require "set"
require_relative "catalog/dsl"

module AccessGrant
  # In-memory permission catalog built from {AccessGrant.permissions}.
  #
  # Entries are hashes with keys +:key+, +:description+, +:category+.
  # Persist them with {AccessGrant::Sync.call}.
  class Catalog
    # Default description templates for built-in actions (+%<resources>s+ /
    # +%<resource>s+ filled from the pluralized resource segment).
    DEFAULT_TEMPLATES = {
      "index" => "Can view list of %<resources>s",
      "show" => "Can view details of a %<resource>s",
      "create" => "Can create a new %<resource>s",
      "update" => "Can update an existing %<resource>s",
      "destroy" => "Can delete an existing %<resource>s"
    }.freeze

    def initialize
      @entries = {}
    end

    # @return [Array<Hash>] catalog entries sorted by +:key+
    def entries
      @entries.values.sort_by { |entry| entry[:key] }
    end

    # Remove all entries.
    #
    # @return [void]
    def clear!
      @entries.clear
    end

    # Clear and evaluate a {DSL} block (replace semantics).
    #
    # @yield DSL
    # @return [void]
    def replace(&block)
      clear!
      DSL.new(self).instance_eval(&block)
    end

    # Insert or override one catalog entry.
    #
    # @param key [String, Symbol] +resource.action+
    # @param description [String]
    # @param category [String] grouping label (often the resource name)
    # @param override [Boolean] when true, replace an existing key instead of raising
    # @return [void]
    # @raise [AccessGrant::Error] invalid or duplicate key (when +override+ is false)
    def add(key, description:, category:, override: false)
      normalized = PermissionKey.normalize!(key)

      raise Error, "Duplicate permission key: #{normalized}" if @entries.key?(normalized) && !override

      @entries[normalized] = { key: normalized, description: description, category: category }
    end

    # Render a {DEFAULT_TEMPLATES} description for +action+ / resource segment.
    #
    # @param action [String, Symbol]
    # @param resource_segment [String] plural resource name (e.g. +"invoices"+)
    # @return [String]
    def template_description(action, resource_segment)
      template = DEFAULT_TEMPLATES.fetch(action.to_s)
      singular = resource_segment.singularize

      format(template, resources: resource_segment, resource: singular)
    end
  end
end
